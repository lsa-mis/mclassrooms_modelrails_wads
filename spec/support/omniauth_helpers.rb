# OmniAuth test-mode plumbing. `mock_auth` is global per-process state, so the
# after-hook RESTORES the pristine snapshot (taken here at load, before any
# example runs) rather than deleting keys — the shipped :default AuthHash must
# survive the first OmniAuth example, or every later example's view of
# mock_auth depends on worker ordering (#851). Specs assign whole keys
# (`mock_auth[:google_oauth2] = AuthHash.new(...)`), so a shallow dup restores
# everything an example can change. spec/omniauth_mock_hygiene_spec.rb pins it.
module OmniauthMockHygiene
  PRISTINE_MOCK_AUTH = OmniAuth.config.mock_auth.dup.freeze
end

RSpec.configure do |config|
  config.before(:each) do
    OmniAuth.config.test_mode = true
  end

  config.after(:each) do
    OmniAuth.config.mock_auth.replace(OmniauthMockHygiene::PRISTINE_MOCK_AUTH.dup)
  end
end
