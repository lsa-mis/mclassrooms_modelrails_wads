# frozen_string_literal: true

require "rails_helper"

# #1038: Resend and Revoke are button_to forms rendered INSIDE the
# members_results Turbo frame, and both controllers answer with a redirect
# carrying a flash. Without an explicit `_top` target Turbo frames that
# redirect into members_results, so the magic-link reveal and the notice —
# both rendered outside the frame — are fetched and thrown away. The user
# clicks and nothing visibly happens.
RSpec.describe "Invitation row actions escape the members frame", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }
  # Seed-agnostic: CI seeds the global roles, local rspec does not.
  let!(:role) { Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" } }

  before { sign_in_via_form(user) }

  it "shows the refreshed magic link and its notice after Resend" do
    create(:invitation, :magic_link, invitable: workspace, role: role, invited_by: user)
    visit workspace_members_path(workspace)

    click_button I18n.t("workspaces.members.index.pending_invitations.resend")

    expect(page).to have_css("#magic_link_reveal")
    expect(page).to have_css("#magic_link_reveal input[data-copy-target='source'][value*='/invitations/']")
    expect(page).to have_text(
      I18n.t("workspaces.invitations.resends.create.magic_link_refreshed")
    )
  end

  it "shows the resent notice after Resend on an email invitation" do
    create(:invitation, invitable: workspace, role: role, invited_by: user,
                        email: "invitee@example.com")
    visit workspace_members_path(workspace)

    click_button I18n.t("workspaces.members.index.pending_invitations.resend")

    expect(page).to have_text(I18n.t("workspaces.invitations.resends.create.resent"))
  end

  it "shows the revoked notice after Revoke" do
    create(:invitation, invitable: workspace, role: role, invited_by: user,
                        email: "invitee@example.com")
    visit workspace_members_path(workspace)

    click_button I18n.t("workspaces.members.index.pending_invitations.revoke")

    expect(page).to have_text(I18n.t("workspaces.invitations.destroy.revoked"))
  end
end
