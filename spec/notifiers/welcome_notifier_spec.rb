# frozen_string_literal: true

require "rails_helper"

RSpec.describe WelcomeNotifier, type: :notifier do
  let(:user) { create(:user, first_name: "Jane") }

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
  end

  def events
    Noticed::Event.where(type: described_class.name)
  end

  describe "declarations" do
    it "is :account_access" do
      expect(described_class.category_name).to eq "account_access"
    end

    it "declares severity :info" do
      expect(described_class.severity_name).to eq :info
    end

    it "has no email delivery method — a new account is already in the app" do
      expect(described_class.delivery_methods.keys).not_to include(:email)
    end
  end

  describe "trigger" do
    # The regression this notifier is one callback away from causing: `User`
    # has `after_create :onboard_workspace`, so a callback-fired welcome would
    # ride every factory user and shift every notification count in the suite.
    it "does not fire for a factory-built user" do
      expect { create(:user) }.not_to change { events.count }
    end

    it "leaves a factory-built user with no notifications of any kind" do
      expect { create(:user) }.not_to change { Noticed::Notification.count }
    end
  end

  describe "rendering" do
    it "greets the recipient and points at their notification preferences" do
      described_class.with(record: user).deliver(nil)
      notification = events.last.notifications.first

      expect(notification.message).to eq(
        I18n.t("notifications.welcome.message", user_name: "Jane")
      )
      expect(notification.url).to eq(
        Rails.application.routes.url_helpers.edit_settings_notification_preferences_path
      )
    end
  end

  describe "preference gating" do
    it "skips in-app when the recipient has the account_access category off" do
      prefs = create(:user_preferences, user: user)
      np = prefs.notification_preferences.deep_dup
      np["notification_types"]["account_access"] = false
      prefs.update!(notification_preferences: np)

      described_class.with(record: user).deliver(nil)

      expect(Noticed::Notification.where(recipient: user,
                                         type: "#{described_class.name}::Notification").count).to eq 0
    end
  end
end
