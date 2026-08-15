require "rails_helper"

RSpec.describe "Sessions new-device detection", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  describe "POST /session — successful sign-in" do
    it "fires SignInFromNewDeviceNotifier on the first sign-in from a browser" do
      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15" }
      }.to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }.by(1)
    end

    it "records the browser fingerprint on the user" do
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15" }

      expect(user.reload.last_known_browsers).not_to be_empty
      entry = user.last_known_browsers.first
      expect(entry).to include("digest", "first_seen_at", "last_seen_at")
    end

    it "does NOT re-fire the notifier on a subsequent sign-in from the same browser" do
      ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15"
      # First sign-in primes the fingerprint.
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }, headers: { "User-Agent" => ua }
      delete session_path

      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => ua }
      }.not_to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }
    end

    it "fires the notifier when the user signs in from a different browser" do
      first_ua  = "Mozilla/5.0 (Macintosh) Safari"
      second_ua = "Mozilla/5.0 (Windows NT 10.0) Chrome/120"

      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }, headers: { "User-Agent" => first_ua }
      delete session_path

      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => second_ua }
      }.to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }.by(1)
    end

    # Security regression guard: prior to folding the browser digest into the
    # idempotency_key, two distinct devices signing in within the same minute
    # would collapse on the dedup index — the second alert would be silently
    # swallowed. That's a real attack surface (phisher signs in seconds after
    # the legit user). Lock this in with a fully-realistic request flow that
    # does NOT use travel/time-helpers.
    it "fires for two distinct devices signing in within the same minute" do
      first_ua  = "Mozilla/5.0 (Macintosh) Safari"
      second_ua = "Mozilla/5.0 (Windows NT 10.0) Chrome/120"

      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }, headers: { "User-Agent" => first_ua }
      delete session_path

      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => second_ua }
      }.to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }.by(1)

      events = Noticed::Event.where(type: "SignInFromNewDeviceNotifier")
      expect(events.count).to eq 2
      expect(events.pluck(:idempotency_key).uniq.size).to eq 2
    end

    it "does not fire on a failed sign-in attempt" do
      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "wrongpassword"
        }, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh)" }
      }.not_to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }
    end
  end

  describe "POST /session — browser version bumps" do
    it "does not re-fire the notifier when only the browser version changed" do
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) Chrome/126.0.0.0" }
      delete session_path

      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5_1) Chrome/127.0.1.2" }
      }.not_to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }
    end
  end

  describe "POST /session — new_device_notification flag" do
    around do |example|
      original = Rails.configuration.x.session.new_device_notification
      Rails.configuration.x.session.new_device_notification = false
      example.run
    ensure
      Rails.configuration.x.session.new_device_notification = original
    end

    it "suppresses the alert but still records the fingerprint when disabled" do
      expect {
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh) Chrome/126.0" }
      }.not_to change { Noticed::Event.where(type: "SignInFromNewDeviceNotifier").count }

      expect(user.reload.last_known_browsers).not_to be_empty
    end
  end

  # The new-device hook is best-effort: a DB/queue hiccup must never break
  # sign-in. But the rescue is narrowed to ActiveRecord errors (on this
  # SQLite + Solid Queue stack, even a "queue down" surfaces as one), so a
  # genuine programming bug propagates instead of being silently masked.
  describe "POST /session — device-detection error handling" do
    let(:mac_ua) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15" }

    it "swallows infrastructure (ActiveRecord) errors so sign-in still succeeds" do
      allow(SignInFromNewDeviceNotifier).to receive(:with)
        .and_raise(ActiveRecord::StatementInvalid.new("simulated DB hiccup"))

      post session_path,
        params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" },
        headers: { "User-Agent" => mac_ua }

      expect(response).to have_http_status(:redirect)
      expect(user.sessions.count).to eq(1)
    end

    it "lets an unexpected programming error surface instead of masking it" do
      allow(SignInFromNewDeviceNotifier).to receive(:with)
        .and_raise(NoMethodError.new("undefined method 'boom'"))

      expect {
        post session_path,
          params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" },
          headers: { "User-Agent" => mac_ua }
      }.to raise_error(NoMethodError)
    end
  end
end
