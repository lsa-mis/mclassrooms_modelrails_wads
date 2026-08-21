require "rails_helper"

RSpec.describe UnreadNotificationSummary do
  let(:user) { create(:user) }

  describe "#to_h" do
    it "returns count 0 and nil severity when there are no unread notifications" do
      expect(described_class.new(user).to_h).to eq(count: 0, severity: nil)
    end

    it "sums the per-notifier counts and picks the highest-ranked severity" do
      allow(user).to receive(:unread_notification_breakdown).and_return(
        "PasswordChangedNotifier"      => 1, # :danger
        "WorkspaceMemberAddedNotifier" => 2  # :success
      )

      expect(described_class.new(user).to_h).to eq(count: 3, severity: :danger)
    end

    it "ranks warning above info above success" do
      allow(user).to receive(:unread_notification_breakdown).and_return(
        "WorkspaceCapacityApproachingNotifier" => 1, # :warning
        "WorkspaceInvitationReceivedNotifier"  => 1  # :info
      )

      expect(described_class.new(user).to_h[:severity]).to eq(:warning)
    end

    it "falls back to :info and logs a warning for a stale notifier class" do
      allow(user).to receive(:unread_notification_breakdown).and_return("DeletedNotifier" => 1)
      expect(Rails.logger).to receive(:warn).with(/Stale notifier class.*DeletedNotifier/)

      expect(described_class.new(user).to_h).to eq(count: 1, severity: :info)
    end

    it "resolves around stale classes without short-circuiting the valid ones" do
      allow(user).to receive(:unread_notification_breakdown).and_return(
        "DeletedNotifierA"             => 1,
        "WorkspaceMemberAddedNotifier" => 1 # :success — outranked by the :info fallback
      )
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(user).to_h).to eq(count: 2, severity: :info)
    end

    it "queries the unread breakdown exactly once per instance" do
      expect(user).to receive(:unread_notification_breakdown).once.and_return({})
      described_class.new(user).to_h
    end
  end

  describe "SEVERITY_RANK" do
    it "ranks danger > warning > info > success and is frozen" do
      expect(described_class::SEVERITY_RANK).to eq(danger: 4, warning: 3, info: 2, success: 1)
      expect(described_class::SEVERITY_RANK).to be_frozen
    end
  end
end
