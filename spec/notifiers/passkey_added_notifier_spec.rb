# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasskeyAddedNotifier, type: :notifier do
  let(:user) { create(:user, first_name: "Ada") }

  describe ".category" do
    it "is :security" do
      expect(described_class.category_name).to eq "security"
    end
  end

  describe "#message" do
    it "renders the passkey-added message with the user's name" do
      described_class.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.message).to include("passkey")
      expect(notification.message).to include("Ada")
    end
  end

  describe "#url" do
    it "points at the passkeys settings page" do
      described_class.with(record: user).deliver(user)
      expect(user.notifications.last.url).to eq(
        Rails.application.routes.url_helpers.settings_passkeys_path
      )
    end
  end
end
