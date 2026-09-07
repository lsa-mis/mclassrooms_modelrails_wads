# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceInvitationResentNotifier, type: :notifier do
  let(:workspace) { create(:workspace) }
  let(:inviter) { create(:user) }
  let(:invitation) do
    create(:invitation,
           invitable: workspace,
           email: "newcomer@example.com",
           invited_by: inviter)
  end

  describe ".category" do
    it "is :account_access" do
      expect(described_class.category_name).to eq "account_access"
    end
  end

  describe "dispatching" do
    it "delivers to the inviter (not the invitee) and creates a Noticed::Notification row" do
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

    it "permits a fresh dispatch after the 1-minute idempotency bucket rolls over" do
      now = Time.current.beginning_of_minute
      travel_to(now) do
        described_class.with(record: invitation).deliver(inviter)
      end
      travel_to(now + 61.seconds) do
        result = described_class.with(record: invitation).deliver(inviter)
        expect(result).to eq :delivered
      end
      expect(Noticed::Event.where(type: described_class.name).count).to eq 2
    end
  end

  describe "#message" do
    it "renders the localized resend message with invitee email and workspace name" do
      described_class.with(record: invitation).deliver(inviter)
      notification = inviter.notifications.last
      expect(notification.message).to eq(
        I18n.t("notifications.workspace_invitation_resent.message",
               invitee_email: "newcomer@example.com",
               workspace: workspace.name)
      )
    end

    it "returns the placeholder copy when the invitation has been deleted" do
      described_class.with(record: invitation).deliver(inviter)
      invitation.destroy
      notification = inviter.notifications.last
      expect(notification.message).to eq(I18n.t("notifications.placeholder"))
    end
  end

  describe "#url" do
    it "links back to the workspace members page for the invitation's workspace" do
      described_class.with(record: invitation).deliver(inviter)
      notification = inviter.notifications.last
      expect(notification.url).to eq(
        Rails.application.routes.url_helpers.workspace_members_path(workspace)
      )
    end

    it "returns the placeholder copy when the invitation has been deleted" do
      described_class.with(record: invitation).deliver(inviter)
      invitation.destroy
      notification = inviter.notifications.last
      expect(notification.url).to eq(I18n.t("notifications.placeholder"))
    end
  end
end
