# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceInvitationExpiringSweepJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:workspace) { create(:workspace) }
  let(:inviter) { create(:user) }
  let(:invitee) { create(:user) }

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    clear_enqueued_jobs
  end

  describe "#perform" do
    it "dispatches WorkspaceInvitationExpiringSoonNotifier for invitations expiring within 24 hours" do
      invitation = create(:invitation,
                          invitable: workspace,
                          email: invitee.email_address,
                          invited_by: inviter,
                          expires_at: 12.hours.from_now)

      expect {
        described_class.perform_now
      }.to change { Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").count }.by(1)

      event = Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").last
      expect(event.record_id).to eq invitation.id
      expect(event.record_type).to eq "Invitation"
    end

    it "does NOT dispatch for invitations expiring outside the 24-hour window" do
      create(:invitation,
             invitable: workspace,
             email: invitee.email_address,
             invited_by: inviter,
             expires_at: 5.days.from_now)

      expect {
        described_class.perform_now
      }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").count }
    end

    it "does NOT dispatch for already-accepted invitations" do
      create(:invitation,
             invitable: workspace,
             email: invitee.email_address,
             invited_by: inviter,
             expires_at: 12.hours.from_now,
             status: "accepted",
             accepted_at: 1.hour.ago,
             accepted_by: invitee)

      expect {
        described_class.perform_now
      }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").count }
    end

    it "does NOT dispatch for already-declined invitations" do
      create(:invitation,
             invitable: workspace,
             email: invitee.email_address,
             invited_by: inviter,
             expires_at: 12.hours.from_now,
             status: "declined",
             declined_at: 1.hour.ago)

      expect {
        described_class.perform_now
      }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").count }
    end

    it "skips magic-link invitations (email is nil)" do
      create(:invitation, :magic_link,
             invitable: workspace,
             invited_by: inviter,
             expires_at: 12.hours.from_now)

      expect {
        described_class.perform_now
      }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").count }
    end

    it "skips invitations whose email does not match a known User" do
      create(:invitation,
             invitable: workspace,
             email: "ghost@example.com",
             invited_by: inviter,
             expires_at: 12.hours.from_now)

      expect {
        described_class.perform_now
      }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").count }
    end

    it "dispatches one Notifier per matching invitation when several are in the window" do
      invitee_b = create(:user)
      create(:invitation,
             invitable: workspace,
             email: invitee.email_address,
             invited_by: inviter,
             expires_at: 8.hours.from_now)
      create(:invitation,
             invitable: workspace,
             email: invitee_b.email_address,
             invited_by: inviter,
             expires_at: 18.hours.from_now)

      expect {
        described_class.perform_now
      }.to change { Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").count }.by(2)
    end

    it "does NOT dispatch for invitations that have already expired" do
      create(:invitation,
             invitable: workspace,
             email: invitee.email_address,
             invited_by: inviter,
             expires_at: 1.hour.ago)

      expect {
        described_class.perform_now
      }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").count }
    end

    # Integration test for the seam between the sweep job (which fires every 6
    # hours) and the day-bucket idempotency override on
    # WorkspaceInvitationExpiringSoonNotifier. The sweep spec covers query +
    # dispatch logic; the Notifier spec covers idempotency in isolation. This
    # asserts they compose: two sweeps in the same UTC day produce ONE event +
    # ONE notification per invitation, not two — even though the second sweep
    # passes the same invitation back through the dispatch path.
    it "deduplicates notifications when sweep runs twice within a day" do
      # Anchor mid-day so the +5h second tick stays inside the same UTC day
      # (the day-bucket key is keyed off `Time.current.to_date.iso8601`).
      anchor = Time.utc(2026, 5, 4, 8, 0, 0)

      travel_to(anchor) do
        create(:invitation,
               invitable: workspace,
               email: invitee.email_address,
               invited_by: inviter,
               # 12h from anchor → still in 24h window on the +5h re-run.
               expires_at: anchor + 12.hours)

        described_class.perform_now
      end

      travel_to(anchor + 5.hours) do
        described_class.perform_now
      end

      expect(
        Noticed::Event.where(type: "WorkspaceInvitationExpiringSoonNotifier").count
      ).to eq 1
      expect(
        Noticed::Notification.where(
          recipient: invitee,
          type: "WorkspaceInvitationExpiringSoonNotifier::Notification"
        ).count
      ).to eq 1
    end
  end
end
