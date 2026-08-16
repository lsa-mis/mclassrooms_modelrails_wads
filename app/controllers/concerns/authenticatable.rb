module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end

    # Inverse guard: pages only useful when signed out (registration, sign-in,
    # magic-link request, password-reset request). Authenticated visitors get
    # redirected to root so they don't see a confusing "Create your account"
    # form while they're already signed in.
    def require_unauthenticated_access(**options)
      before_action :redirect_if_authenticated, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def redirect_if_authenticated
      redirect_to authenticated_home_path, notice: t("authentication.already_signed_in") if resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      token = cookies.signed[:session_id]
      return unless token

      session = Session.find_by(id: token)
      if session && !session.expired?
        session.touch_last_active!
        return session
      end

      # A cookie was presented but no live session backs it — expired, swept, or
      # revoked. Drop the stale cookie and remember it so request_authentication
      # can tell the user why they landed on sign-in (an announced flash), rather
      # than silently dumping them on a login form.
      cookies.delete(:session_id)
      @stale_session_cookie = true
      nil
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.fullpath
      flash[:alert] = t("authentication.session_expired") if @stale_session_cookie
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || authenticated_home_path
    end

    # The post-sign-in home for an authenticated user with no saved return_to.
    # Workspace-agnostic (a user may have no workspace under :none onboarding).
    # Calls resume_session in case require_authentication was skipped (e.g.
    # email-verification show, which allows unauthenticated access).
    #
    # Fork seam: override this method in ApplicationController to send signed-in
    # users somewhere other than root — see app/docs/developer/forking.md.
    def authenticated_home_path
      resume_session
      root_path
    end

    # Session keys that must survive login. Everything else in the pre-auth
    # session hash is dropped at the privilege boundary (reset_session below).
    # Deliberately NOT preserved: current_workspace_id (re-derived per request),
    # return_to_after_reauthentication and reauthentication_code_sent (only set
    # while already authenticated, never during initial sign-in). A fork adding
    # its own pre-auth key registers it here.
    SESSION_KEYS_SURVIVING_LOGIN = %i[
      return_to_after_authenticating pending_invitation_token pending_join_token
      okta_id_token
    ].freeze
    # okta_id_token (fork, RP-initiated logout D4): stashed at OAuth callback
    # time — BEFORE start_new_session_for in the same request, and in the
    # deferred-verification flow an entire session earlier — so the reset here
    # would otherwise wipe it and sign-out would silently skip Okta's
    # end_session_endpoint. See OmniauthCallbacksController#stash_okta_logout_state.

    def start_new_session_for(user)
      # Clear leftover pre-auth session state at the privilege boundary, keeping
      # only the keys the post-login flow needs. Hygiene, not a fixation fix —
      # Rails' encrypted cookie store already prevents a forged session hash and
      # the DB Session row is rotated on every login.
      preserved = SESSION_KEYS_SURVIVING_LOGIN.index_with { |key| session[key] }.compact
      reset_session
      preserved.each { |key, value| session[key] = value }

      user.sessions.create!(
        user_agent: request.user_agent, ip_address: request.remote_ip,
        last_active_at: Time.current, reauthenticated_at: Time.current
      ).tap do |session|
        Current.session = session
        cookies.signed[:session_id] = {
          value: session.id, httponly: true, same_site: :lax,
          expires: Session.absolute_timeout.from_now
        }
        sync_theme_cookie_to_preferences(user)
        detect_and_record_new_device(user)
      end
    end

    # Best-effort new-device detection, once per Session.create!. Only
    # ActiveRecord:: errors are swallowed — even "queue down" surfaces as AR on
    # this stack; anything else is a real bug and propagates (#305).
    # See /docs/developer/application-flows (Best-effort side work at sign-in).
    def detect_and_record_new_device(user)
      ua = request.user_agent.to_s
      os = parse_os_from_user_agent(ua)

      # The flag gates the ALERT only; recording always runs so detection
      # history survives a fork toggling notifications (sessions.rb).
      if Rails.configuration.x.session.new_device_notification && !user.seen_browser?(ua, os)
        SignInFromNewDeviceNotifier.with(record: user, user_agent: ua, os: os).deliver(user)
      end

      user.record_browser!(ua, os)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[new-device-detection] swallowed error for user=#{user.id}: #{e.class}: #{e.message}")
    end

    # Coarse-grained OS label derived from the User-Agent string. Intentionally
    # simple — the digest only needs to be deterministic, not gold-standard
    # device fingerprinting. Order matters (iOS check precedes "Mac" because
    # Mobile Safari UAs contain "Macintosh"-like substrings on iPad).
    def parse_os_from_user_agent(user_agent)
      case user_agent
      when /iPhone|iPad|iPod/      then "iOS"
      when /Android/               then "Android"
      when /Windows/               then "Windows"
      when /Macintosh|Mac OS X/    then "Macintosh"
      when /Linux/                 then "Linux"
      else                              "Other"
      end
    end

    def sync_theme_cookie_to_preferences(user)
      cookie_theme = cookies[:theme]
      return unless cookie_theme.present? && %w[light dark system].include?(cookie_theme)

      preferences = user.preferences || user.create_preferences!
      preferences.update!(theme: cookie_theme) if preferences.theme != cookie_theme
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
