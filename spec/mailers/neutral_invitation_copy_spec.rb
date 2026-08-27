require "rails_helper"

# D4: an invitee has not consented to anything yet, so the invitation itself
# must not disclose the workspace's name. The name appears once the recipient
# opens the accept/decline page — a deliberate, single exposure point.
RSpec.describe "neutral invitation copy", type: :mailer do
  let(:inviter) { create(:user) }
  let(:workspace) { create(:workspace, name: "Distinctive Secret Cabal") }
  let(:invitation) do
    create(:invitation, invitable: workspace, email: "invitee@example.test",
                        invited_by: inviter)
  end

  describe "InvitationMailer#invite" do
    subject(:mail) { InvitationMailer.invite(invitation) }

    it "never names the workspace, in subject or body" do
      expect(mail.subject).not_to include(workspace.name)
      expect(mail.body.encoded).not_to include(workspace.name)
    end

    it "identifies the inviter by their address and names the app instead" do
      expect(mail.subject).to include(I18n.t("application.name"))
      expect(mail.body.encoded).to include(inviter.email_address)
    end
  end

  # D4 names invite AND invite_client. The client variant matters at least as
  # much: it goes to an external party who may have no relationship with the
  # organisation at all, and it was disclosing the project's name.
  describe "InvitationMailer#invite_client" do
    let(:project) { create(:project, workspace: workspace, name: "Codename Bluebird") }
    let(:client_invitation) do
      create(:invitation, :client, invitable: project, email: "client@example.test",
                                   invited_by: inviter)
    end
    subject(:mail) { InvitationMailer.invite_client(client_invitation) }

    it "never names the project, in subject or body" do
      expect(mail.subject).not_to include(project.name)
      expect(mail.body.encoded).not_to include(project.name)
    end

    it "never names the workspace either" do
      expect(mail.body.encoded).not_to include(workspace.name)
    end

    it "identifies the inviter by their address and names the app instead" do
      expect(mail.subject).to include(I18n.t("application.name"))
      expect(mail.body.encoded).to include(inviter.email_address)
    end
  end

  describe "WorkspaceInvitationExpiringSoonNotifier" do
    it "never names the workspace in the in-app message" do
      WorkspaceInvitationExpiringSoonNotifier.with(record: invitation).deliver(inviter)
      notification = inviter.notifications.order(:created_at).last

      expect(notification.message).not_to include(workspace.name)
    end
  end

  describe "the dead received-notifier" do
    it "no longer exists" do
      expect(defined?(WorkspaceInvitationReceivedNotifier)).to be_nil
    end

    it "leaves no locale keys behind" do
      expect(I18n.exists?("notifications.workspace_invitation_received")).to be(false)
    end
  end
end
