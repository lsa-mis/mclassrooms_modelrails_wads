# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceInvitationAcceptedNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  let(:workspace) { create(:workspace) }
  let(:inviter) { create(:user) }
  let(:accepter) { create(:user) }
  let(:invitation) do
    create(:invitation,
           invitable: workspace,
           email: accepter.email_address,
           invited_by: inviter,
           accepted_by: accepter,
           accepted_at: Time.current)
  end

  describe ".category" do
    it "is :workspace_activity" do
      expect(described_class.category_name).to eq "workspace_activity"
    end
  end

  describe "dispatching" do
    it "delivers to the inviter and creates a Noticed::Notification row" do
      result = described_class.with(record: invitation).deliver(inviter)
      expect(result).to eq :delivered
      expect(inviter.notifications.count).to eq 1
    end

    it "auto-populates idempotency_key on the event column" do
      described_class.with(record: invitation).deliver(inviter)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    it "deduplicates concurrent dispatches within the same minute" do
      freeze_time do
        described_class.with(record: invitation).deliver(inviter)
        result = described_class.with(record: invitation).deliver(inviter)
        expect(result).to eq :deduplicated
        expect(Noticed::Event.where(type: described_class.name).count).to eq 1
      end
    end

    it "does not enqueue any NotificationMailer email job (in-app + digest only)" do
      expect {
        described_class.with(record: invitation).deliver(inviter)
        # Drain the EventJob so any per-recipient deliveries also get enqueued.
        perform_enqueued_jobs(only: Noticed::EventJob)
      }.not_to have_enqueued_mail
    end
  end

  describe "preferences gating" do
    let!(:prefs) { create(:user_preferences, user: inviter) }

    it "still routes through workspace_activity (does NOT bypass DND)" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
      described_class.with(record: invitation).deliver(inviter)
      notification = inviter.notifications.last
      expect(notification.recipient_pref(:in_app)).to be false
      expect(notification.recipient_pref(:email)).to be false
    end

    it "permits in-app + email under default preferences (workspace_activity)" do
      described_class.with(record: invitation).deliver(inviter)
      notification = inviter.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:email)).to be true
    end
  end

  describe "#message" do
    it "renders the localized accepted message with accepter and workspace context" do
      described_class.with(record: invitation).deliver(inviter)
      notification = inviter.notifications.last
      expect(notification.message).to eq(
        I18n.t("notifications.workspace_invitation_accepted.message",
               accepter: accepter.email_address,
               workspace: workspace.name)
      )
    end

    context "when invitation invitable is a Project" do
      let(:project) { create(:project, workspace: workspace) }
      let(:project_invitation) do
        create(:invitation,
               invitable: project,
               email: accepter.email_address,
               invited_by: inviter,
               accepted_by: accepter,
               accepted_at: Time.current,
               project_role: "editor")
      end

      it "uses the project's workspace name in the message" do
        described_class.with(record: project_invitation).deliver(inviter)
        notification = inviter.notifications.last
        expect(notification.message).to eq(
          I18n.t("notifications.workspace_invitation_accepted.message",
                 accepter: accepter.email_address,
                 workspace: workspace.name)
        )
      end
    end
  end

  describe "Invitation#after_update_commit trigger" do
    it "fires the notifier when an invitation transitions to accepted" do
      pending_invitation = create(:invitation,
                                  invitable: workspace,
                                  email: accepter.email_address,
                                  invited_by: inviter)
      expect {
        pending_invitation.update!(
          status: "accepted",
          accepted_by: accepter,
          accepted_at: Time.current
        )
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
      expect(inviter.notifications.count).to eq 1
    end

    it "does not fire when the inviter is also the accepter (self-accept edge)" do
      pending_invitation = create(:invitation,
                                  invitable: workspace,
                                  email: inviter.email_address,
                                  invited_by: inviter)
      expect {
        pending_invitation.update!(
          status: "accepted",
          accepted_by: inviter,
          accepted_at: Time.current
        )
      }.not_to change { Noticed::Event.where(type: described_class.name).count }
    end
  end
end
