# frozen_string_literal: true

require "rails_helper"

RSpec.describe SignInFromNewDeviceNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  def create_ada
    create(:user, email_address: "ada@example.com", first_name: "Ada")
  end

  def user_agent
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15"
  end

  def os
    "Macintosh"
  end

  def create_prefs_with_quiet_hours(user)
    prefs = create(:user_preferences, user: user)
    prefs.update!(notification_preferences:
      prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
    prefs
  end

  describe ".category" do
    it "is :security" do
      expect(described_class.category_name).to eq "security"
    end

    it "auto-registers as a security notifier type" do
      expect(ApplicationNotifier.notifier_class_names_for("security")).to include(described_class.name)
    end
  end

  describe "dispatching" do
    it "delivers an in-app notification to the user" do
      user = create_ada
      result = described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
      expect(result).to eq :delivered
      expect(user.notifications.count).to eq 1
    end

    it "auto-populates idempotency_key on the event column" do
      user = create_ada
      described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    it "deduplicates same-device dispatches within the same minute (legitimate retry case)" do
      user = create_ada
      freeze_time do
        described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        result = described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        expect(result).to eq :deduplicated
      end
    end

    # Two devices in one minute must not share an idempotency key: the
    # notifier folds the browser digest into the seed so neither is dropped.
    it "delivers both events when two distinct devices sign in within the same minute" do
      user = create_ada
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
      user = create_ada
      create(:user_preferences, user: user)
      expect {
        described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :sign_in_from_new_device)
    end
  end

  describe "security category bypasses DND" do
    it "still permits in-app under DND" do
      user = create_ada
      create_prefs_with_quiet_hours(user)
      described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
    end

    it "still enqueues email under DND (security never goes silent)" do
      user = create_ada
      create_prefs_with_quiet_hours(user)
      expect {
        described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :sign_in_from_new_device)
    end
  end

  describe "preferences gating" do
    # Security ignores every opt-out mechanism by design
    # (NotificationPreferences#allow? short-circuits at Step 1).
    it "still enqueues email when the security category is disabled and quiet hours are active" do
      user = create_ada
      prefs = create(:user_preferences, user: user)
      # Email-channel opt-out is the one thing security still respects;
      # in-app stays on regardless.
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
      user = create_ada
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
      user = create_ada
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
      user = create_ada
      described_class.with(record: user, user_agent: user_agent, os: os).deliver(user)
      notification = user.notifications.last
      expect(notification.message).to eq(
        I18n.t("notifications.sign_in_from_new_device.message", os: os)
      )
    end
  end
end
