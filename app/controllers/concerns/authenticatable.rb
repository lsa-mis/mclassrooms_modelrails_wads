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
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
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

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
        sync_theme_cookie_to_preferences(user)
        detect_and_record_new_device(user)
      end
    end

    # Fires the SignInFromNewDeviceNotifier when the (user_agent, os) digest
    # is novel for this user, then records the fingerprint either way. Called
    # from start_new_session_for so it runs once per Session.create! — i.e.
    # exactly the moment we recognize as "successful sign-in" — and not on
    # every authenticated request (resume_session does not call this).
    #
    # Best-effort: a DB/queue hiccup here MUST NOT break sign-in. Both writes
    # this method makes (the Notifier's bulk insert, record_browser!'s
    # update_column) go through ActiveRecord, and on this SQLite + Solid Queue
    # stack even a "queue down" surfaces as an ActiveRecord error — so that is
    # the only class we swallow. A non-AR failure (e.g. NoMethodError) is a real
    # bug and propagates rather than being silently masked (#305).
    def detect_and_record_new_device(user)
      ua = request.user_agent.to_s
      os = parse_os_from_user_agent(ua)

      unless user.seen_browser?(ua, os)
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
