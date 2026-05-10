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

  def deliver_password_changed_at(time, recipient: user)
    travel_to(time) do
      PasswordChangedNotifier.with(record: recipient).deliver(recipient)
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

      it "preserves security-category notifications under the 1-year floor" do
        old_security = deliver_password_changed_at(180.days.ago)
        old_security.update!(read_at: 180.days.ago)

        described_class.perform_now

        expect(Noticed::Notification.where(id: old_security.id)).to exist,
          "security notification within 1-year floor should be kept regardless of retention preference"
      end

      it "deletes security-category notifications older than the 1-year floor" do
        very_old_security = deliver_password_changed_at(400.days.ago)
        very_old_security.update!(read_at: 400.days.ago)

        described_class.perform_now

        expect(Noticed::Notification.where(id: very_old_security.id)).not_to exist
      end
    end

    context "user with retention_days = nil (Never)" do
      before do
        prefs = user.preferences.notification_preferences
        user.preferences.update!(notification_preferences: prefs.merge("retention_days" => nil))
      end

      it "does not delete any read notifications regardless of age" do
        ancient = deliver_workspace_invitation_at(2.years.ago)
        ancient.update!(read_at: 2.years.ago)

        described_class.perform_now

        expect(Noticed::Notification.where(id: ancient.id)).to exist
      end
    end

    context "user without preferences row" do
      it "does not raise" do
        unconfigured = create(:user)

        expect {
          described_class.perform_now
        }.not_to raise_error
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
  end
end
