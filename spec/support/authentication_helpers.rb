module AuthenticationHelpers
  # Sign in a user via the real magic-link flow (email → Continue → token
  # lookup → callback). For system specs, where the session cookie must live
  # in the driven browser, not the Rack::Test cookie jar. Canonical home
  # (#743) — twelve spec-local copies of this once drifted independently.
  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.create_for_email(user.email_address)
    visit magic_link_callback_path(token: token)
    click_button I18n.t("magic_link_callbacks.confirm.sign_in_button")
    # wait: 10 — the confirm POST → redirect → render round-trip outlasts the
    # default wait on loaded CI shards; two unrelated specs flaked here in two
    # days (#796). This helper is the one funnel, so the bump covers every
    # caller without loosening any other wait.
    expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"), wait: 10)
  end

  def sign_in(user)
    if user.has_password?
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }
    else
      # Passwordless users cannot authenticate via password form; create session directly
      # by generating a properly signed session_id cookie matching ActionDispatch's format.
      # Mirror start_new_session_for: a just-signed-in session is active and
      # reauth-fresh, so lifecycle/reauth gates behave as they do in production.
      session_record = user.sessions.create!(
        user_agent: "RSpec", ip_address: "127.0.0.1",
        last_active_at: Time.current, reauthenticated_at: Time.current
      )
      env = Rails.application.env_config
      salt = env["action_dispatch.signed_cookie_salt"]
      secret = env["action_dispatch.key_generator"].generate_key(salt)
      verifier = ActiveSupport::MessageVerifier.new(
        secret,
        digest: "SHA1",
        serializer: ActiveSupport::MessageEncryptor::NullSerializer
      )
      signed_value = verifier.generate(session_record.id.to_s, purpose: "cookie.session_id")
      cookies[:session_id] = signed_value
    end
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
  config.include AuthenticationHelpers, type: :system
end
