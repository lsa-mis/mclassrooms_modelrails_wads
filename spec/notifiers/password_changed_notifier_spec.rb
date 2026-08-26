# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordChangedNotifier, type: :notifier do
  let(:user) { create(:user) }

  describe ".category" do
    it "is :security" do
      expect(described_class.category_name).to eq "security"
    end
  end

  describe "dispatching" do
    it "delivers to the user and creates a Noticed::Notification row" do
      result = described_class.with(record: user).deliver(user)
      expect(result).to eq :delivered
      expect(user.notifications.count).to eq 1
    end

    it "auto-populates idempotency_key on the event column" do
      described_class.with(record: user).deliver(user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    it "deduplicates concurrent dispatches within the same minute" do
      freeze_time do
        described_class.with(record: user).deliver(user)
        result = described_class.with(record: user).deliver(user)
        expect(result).to eq :deduplicated
      end
    end

    # Regression guard for the dedup_seed fix: without it, a change followed
    # by a removal for the same user inside one minute would share the base
    # (class, record.id, minute) key — the removal's #deliver would hit
    # RecordNotUnique and the more consequential alert would be silently
    # dropped. Pinned to one instant so the minute bucket can't roll over
    # between the two deliveries and mask the collision.
    it "delivers both a change and a removal within the same minute bucket, each with its own copy" do
      freeze_time do
        changed_result = described_class.with(record: user, removed: false).deliver(user)
        removed_result = described_class.with(record: user, removed: true).deliver(user)

        expect(changed_result).to eq :delivered
        expect(removed_result).to eq :delivered
        expect(user.notifications.count).to eq 2

        expect(user.notifications.includes(:event).map(&:message)).to contain_exactly(
          I18n.t("notifications.password_changed.message", user_name: user.first_name),
          I18n.t("notifications.password_removed.message", user_name: user.first_name)
        )
      end
    end
  end

  describe "#message" do
    it "renders the password_changed copy when removed is absent (backward compatible)" do
      described_class.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.message).to eq(
        I18n.t("notifications.password_changed.message", user_name: user.first_name)
      )
    end

    it "renders the password_removed copy when removed: true" do
      described_class.with(record: user, removed: true).deliver(user)
      notification = user.notifications.last
      expect(notification.message).to eq(
        I18n.t("notifications.password_removed.message", user_name: user.first_name)
      )
    end
  end

  describe "security category bypasses DND" do
    let!(:prefs) { create(:user_preferences, user: user) }

    it "still delivers email under DND" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
      described_class.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:email)).to be true
    end

    it "still permits in-app under DND" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
      described_class.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
    end
  end
end
