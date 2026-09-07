# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationCleanupJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    user.create_preferences!
  end

  # Build a notifier event + user-recipient notification with a specific
  # read_at timestamp by traveling to the past.
  def deliver_workspace_invitation_at(time, recipient: user)
    travel_to(time) do
      invitation = create(:invitation, invitable: create(:workspace),
                          email: recipient.email_address, invited_by: create(:user))
      WorkspaceInvitationAcceptedNotifier.with(record: invitation).deliver(recipient)
    end
    recipient.notifications.last
  end

  describe "#perform" do
    context "user with retention_days = 90" do
      before do
        prefs = user.preferences.notification_preferences
        user.preferences.update!(notification_preferences: prefs.merge("retention_days" => 90))
      end

      it "deletes read notifications older than the (days + 2) grace period" do
        old = deliver_workspace_invitation_at(100.days.ago)
        old.update!(read_at: 100.days.ago)

        expect {
          described_class.perform_now
        }.to change { Noticed::Notification.where(id: old.id).count }.from(1).to(0)
      end

      it "keeps read notifications inside the 2-day grace window (91 days old)" do
        in_grace = deliver_workspace_invitation_at(91.days.ago)
        in_grace.update!(read_at: 91.days.ago)

        described_class.perform_now

        expect(Noticed::Notification.where(id: in_grace.id)).to exist
      end

      it "keeps read notifications under the retention threshold (60 days old)" do
        recent = deliver_workspace_invitation_at(60.days.ago)
        recent.update!(read_at: 60.days.ago)

        described_class.perform_now

        expect(Noticed::Notification.where(id: recent.id)).to exist
      end

      it "never deletes unread notifications regardless of age" do
        ancient_unread = deliver_workspace_invitation_at(2.years.ago)
        # read_at intentionally left nil

        described_class.perform_now

        expect(Noticed::Notification.where(id: ancient_unread.id)).to exist
      end
    end

    context "user without preferences row" do
      it "sweeps at the default retention, matching what the index hint tells them" do
        unconfigured = create(:user)
        old = deliver_workspace_invitation_at(100.days.ago, recipient: unconfigured)
        old.update!(read_at: 100.days.ago)
        recent = deliver_workspace_invitation_at(50.days.ago, recipient: unconfigured)
        recent.update!(read_at: 50.days.ago)

        described_class.perform_now

        expect(Noticed::Notification.where(id: old.id)).not_to exist
        expect(Noticed::Notification.where(id: recent.id)).to exist
      end
    end

    context "scoping per-user" do
      it "doesn't delete other users' notifications even when their retention says delete" do
        prefs = user.preferences.notification_preferences
        user.preferences.update!(notification_preferences: prefs.merge("retention_days" => 30))
        other_user.create_preferences!  # default 90-day retention

        old_for_user = deliver_workspace_invitation_at(40.days.ago)
        old_for_user.update!(read_at: 40.days.ago)
        recent_for_other = deliver_workspace_invitation_at(40.days.ago, recipient: other_user)
        recent_for_other.update!(read_at: 40.days.ago)

        described_class.perform_now

        expect(Noticed::Notification.where(id: old_for_user.id)).not_to exist
        expect(Noticed::Notification.where(id: recent_for_other.id)).to exist
      end
    end

    context "fault isolation" do
      # A malformed row: retention_days stored as a string. `"90" + 2` raises
      # TypeError inside that user's body and nowhere else — a real data fault,
      # no mocking, so the rescue is exercised for the reason it exists.
      def corrupt_retention_for(someone)
        someone.create_preferences! unless someone.preferences
        prefs = someone.preferences.notification_preferences
        someone.preferences.update_column(:notification_preferences, prefs.merge("retention_days" => "90"))
      end

      it "reports one user's failure and still sweeps the next user" do
        corrupt_retention_for(user)
        other_user.create_preferences!
        old_for_other = deliver_workspace_invitation_at(100.days.ago, recipient: other_user)
        old_for_other.update!(read_at: 100.days.ago)

        expect(Rails.error).to receive(:report).with(
          instance_of(TypeError),
          hash_including(handled: true, context: hash_including(user_id: user.id))
        )

        expect { described_class.perform_now }.not_to raise_error
        expect(Noticed::Notification.where(id: old_for_other.id)).not_to exist
      end

      it "re-raises when every attempted user failed, so the queue records a failure" do
        corrupt_retention_for(user)
        corrupt_retention_for(other_user)
        allow(Rails.error).to receive(:report)

        expect { described_class.perform_now }.to raise_error(TypeError)
      end
    end

    context "user whose stored retention is an explicit null (a pre-migration Never choice)" do
      it "sweeps at the Never cap, not never" do
        prefs = user.preferences.notification_preferences
        user.preferences.update_column(:notification_preferences, prefs.merge("retention_days" => nil))
        ancient = deliver_workspace_invitation_at(400.days.ago)
        ancient.update!(read_at: 400.days.ago)
        within_cap = deliver_workspace_invitation_at(200.days.ago)
        within_cap.update!(read_at: 200.days.ago)

        described_class.perform_now

        expect(Noticed::Notification.where(id: ancient.id)).not_to exist
        expect(Noticed::Notification.where(id: within_cap.id)).to exist
      end
    end
  end
end
