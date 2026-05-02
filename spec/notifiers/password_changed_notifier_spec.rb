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
  end

  describe "security category bypasses DND" do
    let!(:prefs) { create(:user_preferences, user: user) }

    it "still delivers email under DND" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("do_not_disturb" => true))
      described_class.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:email)).to be true
    end

    it "still permits in-app under DND" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("do_not_disturb" => true))
      described_class.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
    end
  end
end
