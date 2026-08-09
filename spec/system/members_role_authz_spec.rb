require "rails_helper"

# SEC-1 accessibility coverage: the existing members axe spec logs in as the
# Owner, who sees every control. These exercise the *Admin* actor, for whom the
# Owner row renders without an Edit-role link and role pickers omit Owner —
# the branches the owner-actor spec never renders.
RSpec.describe "Members role authorization (admin actor)", type: :system do
  let(:owner) { create(:user, first_name: "Olivia", last_name: "Owner") }
  let(:admin) { create(:user, first_name: "Adam", last_name: "Admin", password: "SecureP@ssw0rd123!") }
  let(:workspace) { create(:workspace, max_members: 50) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    %w[admin member viewer].each { |slug| Role.system_default!(slug) }
    create(:membership, :owner, user: owner, workspace: workspace)
    create(:membership, :admin, user: admin, workspace: workspace)

    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: admin.email_address
    click_button I18n.t("sessions.new.continue")
    token = MagicLinkToken.where(email: admin.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_css("#user-menu-button")
  end

  it "renders the members index (owner row has no edit link) accessibly in both themes" do
    visit workspace_members_path(workspace)
    within "##{ActionView::RecordIdentifier.dom_id(workspace.memberships.find_by(user: owner))}" do
      expect(page).not_to have_link(I18n.t("workspaces.members.index.edit_role"))
    end
    page.execute_script("document.querySelectorAll('[data-controller=\"toast-pill\"], [data-controller=\"toast-card\"]').forEach(el => el.remove())")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "renders the invitation form (Owner omitted from the role select) accessibly in both themes" do
    visit new_workspace_invitation_path(workspace)
    expect(page).to have_select(I18n.t("workspaces.invitations.new.role_label"))
    within "select" do
      expect(page).not_to have_text("Owner")
    end
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
