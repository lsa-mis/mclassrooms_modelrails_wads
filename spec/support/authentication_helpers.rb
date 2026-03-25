module AuthenticationHelpers
  def sign_in(user)
    post session_path, params: {
      email_address: user.email_address,
      password: "SecureP@ssw0rd123!"
    }
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
  config.include AuthenticationHelpers, type: :system
end
