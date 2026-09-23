require "rails_helper"

# These six strings are DIGEST INPUTS, not display labels.
#
# `User.browser_digest(user_agent, os)` hashes the OS label together with the
# version-stripped User-Agent, and the result is the stored device fingerprint.
# So renaming one of these — "Macintosh" to "macOS", say — does not change a
# label anybody sees. It silently invalidates every fingerprint already stored
# for that platform, and every affected user is told they signed in from a new
# device the next time they sign in from the device they have always used.
#
# The parser is private, so this pins the labels through the public path that
# consumes them: sign in with a representative User-Agent and assert the
# recorded digest is the one built from the expected label (#643).
RSpec.describe "Known-device OS labels", type: :request do
  # Representative User-Agent per branch, in the order the parser tests them —
  # the iOS check deliberately precedes the Mac check, because an iPad UA
  # contains a "Macintosh"-like substring and would otherwise label as Mac.
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

  # Android UAs contain "Linux", and iPad UAs contain "Mac OS X". Both would
  # take the wrong branch if the case order were ever rearranged, so the order
  # is pinned rather than assumed.
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
