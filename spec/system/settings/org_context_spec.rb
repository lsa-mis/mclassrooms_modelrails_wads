require "rails_helper"

RSpec.describe "Settings hub — workspace context", type: :system do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Corp") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:sidebar_selector) { "aside[aria-label='#{I18n.t("settings.sidebar.aria_label")}']" }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    viewer_role = Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }
    create(:membership, user: viewer, workspace: workspace, role: viewer_role)
  end

  context "as Owner" do
    before { sign_in_via_form(owner) }

    it "renders workspace-context sidebar with all admin items" do
      visit edit_workspace_path(workspace)

      within(sidebar_selector) do
        expect(page).to have_link(I18n.t("settings.sidebar.items.profile"))
        expect(page).to have_link(I18n.t("settings.sidebar.items.members"))
        expect(page).to have_link(I18n.t("settings.sidebar.items.invitations"))
        expect(page).to have_link(I18n.t("settings.sidebar.items.limits_and_plan"))

        expect(page).not_to have_link(I18n.t("settings.sidebar.items.notifications"))
        expect(page).not_to have_link(I18n.t("settings.sidebar.items.security"))
        expect(page).not_to have_link(I18n.t("settings.sidebar.items.appearance"))
      end
    end

    it "exposes the workspace context via data attribute" do
      visit edit_workspace_path(workspace)
      expect(page).to have_css("[data-workspace-kind='workspace']")
    end

    it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
      visit edit_workspace_path(workspace)

      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  context "as Viewer" do
    before { sign_in_via_form(viewer) }

    # WorkspacePolicy#update? requires the manage_workspace permission, which
    # Viewers don't hold. Hitting edit_workspace_path triggers Pundit's
    # NotAuthorizedError → redirect to workspace_path with the standard
    # not_authorized flash. This is the actual security guarantee; the sidebar
    # never renders because the controller redirects before the view does.
    it "is denied access to the workspace Profile settings page via Pundit" do
      visit edit_workspace_path(workspace)

      expect(page).to have_current_path(workspace_path(workspace))
      expect(page).to have_text(I18n.t("errors.not_authorized"))
    end
  end
end
