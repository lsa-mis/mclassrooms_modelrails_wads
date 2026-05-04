# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceInvitationExpiringSoonNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  let(:workspace) { create(:workspace) }
  let(:inviter) { create(:user) }
  # The invitee is resolved by the scheduled sweep job (Task 9, future PR) via
  # User.find_by(email_address: invitation.email). Construct that linkage by
  # hand here so this spec exercises only the dispatch contract.
  let(:invitee) { create(:user) }
  let(:invitation) do
    create(:invitation,
           invitable: workspace,
           email: invitee.email_address,
           invited_by: inviter,
           expires_at: 24.hours.from_now)
  end

  # Drain the EventJob -> per-channel delivery method -> ActionMailer chain
  # in two passes; perform_enqueued_jobs only performs jobs already enqueued
  # at call time, not jobs added during the run.
  def drain_noticed_jobs
    perform_enqueued_jobs(only: Noticed::EventJob)
    perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
  end

  describe ".category" do
    it "is :account_access" do
      expect(described_class.category_name).to eq "account_access"
    end
  end

  describe "dispatching" do
    it "delivers to the invitee and creates a Noticed::Notification row" do
      result = described_class.with(record: invitation).deliver(invitee)
      expect(result).to eq :delivered
      expect(invitee.notifications.count).to eq 1
    end

    it "auto-populates idempotency_key on the event column" do
      described_class.with(record: invitation).deliver(invitee)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    it "deduplicates concurrent dispatches within the same minute" do
      freeze_time do
        described_class.with(record: invitation).deliver(invitee)
        result = described_class.with(record: invitation).deliver(invitee)
        expect(result).to eq :deduplicated
      end
    end

    it "enqueues a NotificationMailer.workspace_invitation_expiring_soon email under default preferences" do
      create(:user_preferences, user: invitee)
      expect {
        described_class.with(record: invitation).deliver(invitee)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :workspace_invitation_expiring_soon)
    end
  end

  describe "preferences gating" do
    let!(:prefs) { create(:user_preferences, user: invitee) }

    it "suppresses both in-app and email under DND (account_access does NOT bypass)" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("do_not_disturb" => true))

      expect {
        described_class.with(record: invitation).deliver(invitee)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_invitation_expiring_soon)

      notification = invitee.notifications.last
      expect(notification.recipient_pref(:in_app)).to be false
      expect(notification.recipient_pref(:email)).to be false
    end

    it "fires in-app but skips email when account_access.email is false" do
      categories = prefs.notification_preferences["categories"].deep_dup
      categories["account_access"]["email"] = false
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("categories" => categories))

      expect {
        described_class.with(record: invitation).deliver(invitee)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_invitation_expiring_soon)

      notification = invitee.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:email)).to be false
    end
  end

  describe "#message" do
    it "renders the localized expiring-soon message with workspace and hours_remaining" do
      freeze_time do
        invitation_in_window = create(:invitation,
                                      invitable: workspace,
                                      email: invitee.email_address,
                                      invited_by: inviter,
                                      expires_at: 24.hours.from_now)
        described_class.with(record: invitation_in_window).deliver(invitee)
        notification = invitee.notifications.last
        expect(notification.message).to eq(
          I18n.t("notifications.workspace_invitation_expiring_soon.message",
                 workspace: workspace.name,
                 hours_remaining: 24)
        )
      end
    end

    context "when invitation invitable is a Project" do
      let(:project) { create(:project, workspace: workspace) }
      let(:project_invitation) do
        create(:invitation,
               invitable: project,
               email: invitee.email_address,
               invited_by: inviter,
               expires_at: 24.hours.from_now,
               project_role: "editor")
      end

      it "uses the project's workspace name in the message" do
        freeze_time do
          described_class.with(record: project_invitation).deliver(invitee)
          notification = invitee.notifications.last
          expect(notification.message).to eq(
            I18n.t("notifications.workspace_invitation_expiring_soon.message",
                   workspace: workspace.name,
                   hours_remaining: 24)
          )
        end
      end
    end
  end
end
