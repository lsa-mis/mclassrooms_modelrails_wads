# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInFromNewDeviceNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  let(:user) { create(:user, email_address: "ada@example.com", first_name: "Ada") }
  let(:user_agent) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15" }
  let(:os) { "Macintosh" }

  # Same draining utility used by the other Notifier specs — Noticed enqueues
  # an EventJob, then a per-channel delivery-method job, then ActionMailer's
  # MailDeliveryJob. perform_enqueued_jobs is non-recursive, so we drain in
  # sequence.
  def drain_noticed_jobs
    perform_enqueued_jobs(only: Noticed::EventJob)
    perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
  end

  describe ".category" do
    it "is :security" do
      expect(described_class.category_name).to eq "security"
    end

    it "auto-registers as a security notifier type" do
      expect(NotificationPreferences.security_notifier_types).to include(described_class.name)
    end
  end

  describe "dispatching" do
    it "delivers an in-app notification to the user" do
      result = described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
      expect(result).to eq :delivered
      expect(user.notifications.count).to eq 1
    end

    it "auto-populates idempotency_key on the event column" do
      described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    it "deduplicates same-device dispatches within the same minute (legitimate retry case)" do
      freeze_time do
        described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        result = described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        expect(result).to eq :deduplicated
      end
    end

    # Security regression guard: the base ApplicationNotifier seeds the
    # idempotency_key from (class, record.id, minute). Because `record` here is
    # the user, two distinct devices signing in within the same minute would
    # collide on that key and the second event would be silently dropped — a
    # real attack surface (phisher signs in seconds after the legit user).
    # SignInFromNewDeviceNotifier overrides populate_idempotency_key to fold
    # the browser digest into the seed so each (user, device, minute) gets a
    # distinct key. This pins that contract in place.
    it "delivers both events when two distinct devices sign in within the same minute" do
      other_ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120"
      other_os = "Windows"

      freeze_time do
        first  = described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        second = described_class.with(record: user, user_agent: other_ua, os: other_os).deliver(user)

        expect(first).to eq :delivered
        expect(second).to eq :delivered

        events = Noticed::Event.where(type: described_class.name).order(:created_at)
        expect(events.count).to eq 2
        expect(events.pluck(:idempotency_key).uniq.size).to eq 2
      end
    end

    it "enqueues NotificationMailer.sign_in_from_new_device under default preferences" do
      create(:user_preferences, user: user)
      expect {
        described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :sign_in_from_new_device)
    end
  end

  describe "security category bypasses DND" do
    let!(:prefs) { create(:user_preferences, user: user) }

    before do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
    end

    it "still permits in-app under DND" do
      described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
    end

    it "still enqueues email under DND (security never goes silent)" do
      expect {
        described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :sign_in_from_new_device)
    end
  end

  describe "preferences gating" do
    # NOTE: security category is structurally non-suppressible per
    # NotificationPreferences#allow? — even if a user disables every channel
    # AND turns off the security notification type AND activates quiet hours,
    # the value object short-circuits at Step 1 and returns true. This test
    # pins that load-bearing invariant in place: security ignores every opt-out
    # mechanism by design.
    let!(:prefs) { create(:user_preferences, user: user) }

    it "still enqueues email when the security category is disabled and quiet hours are active" do
      # v2 contract: security bypasses notification_types[security]=false AND
      # quiet_hours. (It DOES respect delivery_methods.email.enabled=false —
      # see NotificationPreferences#allow? line 54 — a deliberate trade-off
      # so a user who disables email globally isn't forced to receive
      # security email anyway. In-app stays on regardless.)
      np = prefs.notification_preferences.deep_dup
      np["notification_types"]["security"] = false
      np["quiet_hours"] = { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => false }
      prefs.update!(notification_preferences: np)

      expect {
        described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :sign_in_from_new_device)

      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:email)).to be true
    end
  end

  describe "per-recipient throttle" do
    # The mailer method gates on EmailRecipientThrottle.allow! to prevent a
    # coordinated attack from flooding a single inbox via repeated novel-device
    # sign-ins. After the cap is exhausted the mailer becomes a no-op (early
    # return), so the message is never built/delivered even though the job
    # was enqueued. Test cache is :null_store by default — swap to MemoryStore
    # so increment actually counts (mirrors omniauth_callbacks_spec around block).
    around do |ex|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      ex.run
    ensure
      Rails.cache = original
    end

    it "stops delivering once the recipient flood cap is exhausted" do
      EmailRecipientThrottle::CAP.times do
        EmailRecipientThrottle.allow!(user.email_address, kind: :sign_in_from_new_device)
      end

      mail = NotificationMailer.with(
        notification: nil,
        recipient: user,
        record: user
      ).sign_in_from_new_device

      # No-op: ActionMailer treats a method without a `mail()` call as no message.
      expect(mail.message).to be_a(ActionMailer::Base::NullMail)
    end

    it "still delivers below the cap" do
      mail = NotificationMailer.with(
        notification: nil,
        recipient: user,
        record: user
      ).sign_in_from_new_device

      expect(mail.message).not_to be_a(ActionMailer::Base::NullMail)
    end
  end

  describe "#message" do
    it "renders the localized new-device message with the OS substituted" do
      described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
      notification = user.notifications.last
      expect(notification.message).to eq(
        I18n.t("notifications.sign_in_from_new_device.message", os: os)
      )
    end
  end
end
