# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceInvitationDeclinedNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  let(:workspace) { create(:workspace) }
  let(:inviter) { create(:user) }
  let(:decliner_email) { Faker::Internet.email }
  let(:invitation) do
    create(:invitation,
           invitable: workspace,
           email: decliner_email,
           invited_by: inviter,
           declined_at: Time.current,
           status: "declined")
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
        perform_enqueued_jobs(only: Noticed::EventJob)
      }.not_to have_enqueued_mail
    end
  end

  describe "preferences gating" do
    let!(:prefs) { create(:user_preferences, user: inviter) }

    it "still routes through workspace_activity (does NOT bypass DND)" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("do_not_disturb" => true))
      described_class.with(record: invitation).deliver(inviter)
      notification = inviter.notifications.last
      expect(notification.recipient_pref(:in_app)).to be false
      expect(notification.recipient_pref(:email)).to be false
    end

    it "permits in-app + digest under default preferences (workspace_activity)" do
      described_class.with(record: invitation).deliver(inviter)
      notification = inviter.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:digest)).to be true
      expect(notification.recipient_pref(:email)).to be false
    end
  end

  describe "#message" do
    it "renders the localized declined message with decliner email and workspace context" do
      described_class.with(record: invitation).deliver(inviter)
      notification = inviter.notifications.last
      expect(notification.message).to eq(
        I18n.t("notifications.workspace_invitation_declined.message",
               decliner_email: decliner_email,
               workspace: workspace.name)
      )
    end
  end

  describe "Invitation#after_update_commit trigger" do
    it "fires the notifier when an invitation transitions to declined" do
      pending_invitation = create(:invitation,
                                  invitable: workspace,
                                  email: decliner_email,
                                  invited_by: inviter)
      expect {
        pending_invitation.decline!
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
      expect(inviter.notifications.count).to eq 1
    end

    it "does not fire when the invitation email matches the inviter's email_address (self-decline edge)" do
      # Mirror the self-accept guard on notify_accepted: an inviter who declines
      # their own invitation (e.g., bulk-invited themselves, then declined via
      # the magic link) shouldn't ping themselves about it. Decline path has no
      # accepted_by analog, so the guard compares email-vs-inviter.email_address
      # via EmailNormalizer.equivalent? for case + Unicode + IDN safety.
      self_invitation = create(:invitation,
                               invitable: workspace,
                               email: inviter.email_address.upcase, # mixed case to verify normalization
                               invited_by: inviter)
      expect {
        self_invitation.decline!
      }.not_to change { Noticed::Event.where(type: described_class.name).count }
      expect(inviter.notifications.count).to eq 0
    end
  end
end
