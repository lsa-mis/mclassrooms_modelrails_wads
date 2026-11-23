require "rails_helper"

RSpec.describe "Workspace invitations", type: :system do
  include ActiveJob::TestHelper

  describe "creating an email invitation through the form" do
    # The controller does params.require(:invitation), so the form must scope
    # its fields under invitation[...]; a request spec cannot catch that.
    it "creates an Invitation, enqueues the mailer, and shows a success flash" do
      admin = create(:user, first_name: "Owner", last_name: "User")
      workspace = create(:workspace, max_members: 50)
      create(:membership, :owner, user: admin, workspace: workspace)
      sign_in_via_form(admin)
      expect(page).to have_css("#user-menu-button")

      expect {
        visit new_workspace_invitation_path(workspace)
        fill_in I18n.t("workspaces.invitations.new.emails_label"), with: "newcomer@example.com"
        select "Owner", from: I18n.t("workspaces.invitations.new.role_label")
        click_button I18n.t("workspaces.invitations.new.submit")
        expect(page).to have_content(/1 invitation\(s\) sent\. 0 skipped\./)
      }.to change { workspace.invitations.count }.by(1)
        .and have_enqueued_mail(InvitationMailer, :invite)
    end
  end
end
