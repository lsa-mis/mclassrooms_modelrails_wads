module AuthenticationHelpers
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
