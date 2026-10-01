require "rails_helper"

# These labels are digest inputs: renaming one re-alerts every user on that
# platform. Pinned through the public sign-in path (#643).
RSpec.describe "Known-device OS labels", type: :request do
  {
    "iOS" => "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " \
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
    "Android" => "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    "Windows" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Macintosh" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " \
      "(KHTML, like Gecko) Version/18.0 Safari/605.1.15",
    "Linux" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Other" => "curl/8.4.0"
  }.each do |expected_os, user_agent|
    it "records a #{expected_os} sign-in under the #{expected_os.inspect} digest" do
      password = "SecureP@ssw0rd!"
      user = create(:user, password: password, password_confirmation: password)

      post session_path,
           params: { email_address: user.email_address, password: password },
           headers: { "HTTP_USER_AGENT" => user_agent }

      expect(user.reload.last_known_browsers.map { |b| b["digest"] })
        .to include(User.browser_digest(user_agent, expected_os)),
            "signing in with #{user_agent.inspect} did not record the #{expected_os.inspect} " \
            "digest — if the label was renamed, every stored fingerprint for this platform " \
            "is now stale and those users get a spurious new-device alert"
    end
  end

  # Branch order pinned: Android UAs contain Linux, iPad UAs contain Mac OS X.
  it "prefers the more specific platform when a User-Agent matches two branches" do
    password = "SecureP@ssw0rd!"
    android = create(:user, password: password, password_confirmation: password)
    android_ua = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 " \
                 "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    post session_path,
         params: { email_address: android.email_address, password: password },
         headers: { "HTTP_USER_AGENT" => android_ua }

    digests = android.reload.last_known_browsers.map { |b| b["digest"] }
    expect(digests).to include(User.browser_digest(android_ua, "Android"))
    expect(digests).not_to include(User.browser_digest(android_ua, "Linux"))
  end
end
