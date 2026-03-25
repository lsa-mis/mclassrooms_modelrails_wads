RSpec.configure do |config|
  config.before(:each) do
    OmniAuth.config.test_mode = true
  end

  config.after(:each) do
    OmniAuth.config.mock_auth.each_key do |provider|
      OmniAuth.config.mock_auth[provider] = nil
    end
  end
end
