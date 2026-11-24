require "rails_helper"

RSpec.describe "Settings hub — workspace context", type: :system do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Corp") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  # edit_workspace_path (Profile) moved off the settings hub into the workspace
  # shell (nav IA refactor Task 2) — its secondary sub-nav is the equivalent of
  # the old settings-hub <aside> for this page. Members/Limits & Plan are still
  # rendered on the old settings hub (later tasks); they're only linked from
  # here as sibling destinations.
  let(:subnav_selector) { "nav[aria-label='#{I18n.t("settings.sidebar.strip_heading.workspace")}']" }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    create(:membership, :viewer, user: viewer, workspace: workspace)
  end

  context "as Owner" do
    before { sign_in_via_form(owner) }

    it "renders the workspace settings sub-nav with all admin items" do
      visit edit_workspace_path(workspace)

      within(subnav_selector) do
        expect(page).to have_link(I18n.t("settings.sidebar.items.profile"))
        expect(page).to have_link(I18n.t("settings.sidebar.items.members"))
        expect(page).to have_link(I18n.t("settings.sidebar.items.limits_and_plan"))

        expect(page).not_to have_link(I18n.t("settings.sidebar.items.notifications"))
        expect(page).not_to have_link(I18n.t("settings.sidebar.items.security"))
        expect(page).not_to have_link(I18n.t("settings.sidebar.items.appearance"))
      end
    end

    it "exposes the workspace-settings section on the shell's primary nav" do
      visit edit_workspace_path(workspace)
      within("aside[aria-label='#{I18n.t("workspaces.sidebar.aria_label")}']") do
        expect(page).to have_link(I18n.t("workspaces.sidebar.settings"), href: edit_workspace_path(workspace))
      end
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
