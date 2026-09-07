# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationPolicy, type: :policy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  let(:own_notification) do
    PasswordChangedNotifier.with(record: user).deliver(user)
    user.notifications.last
  end

  let(:foreign_notification) do
    PasswordChangedNotifier.with(record: other_user).deliver(other_user)
    other_user.notifications.last
  end

  describe "Scope" do
    subject(:scope) do
      described_class::Scope.new(user, Noticed::Notification.all).resolve
    end

    it "includes the user's own notifications" do
      own_notification
      expect(scope).to include(own_notification)
    end

    it "excludes other users' notifications" do
      foreign_notification
      expect(scope).not_to include(foreign_notification)
    end
  end

  describe "#update?" do
    it "permits the recipient" do
      expect(described_class.new(user, own_notification).update?).to be true
    end

    it "denies a non-recipient" do
      expect(described_class.new(user, foreign_notification).update?).to be false
    end
  end
end
