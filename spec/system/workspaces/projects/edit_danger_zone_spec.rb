require "rails_helper"

RSpec.describe "Project edit danger zone", type: :system do
  let(:creator) { create(:user) }
  let(:project) { create(:project, created_by: creator, name: "Launch Plan") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before { create(:project_membership, :creator, project: project, user: creator) }

  context "as the project creator" do
    before { sign_in_via_form(creator) }

    it "shows an Archive project trigger on the project edit page" do
      visit edit_workspace_project_path(project.workspace, project)
      expect(page).to have_button(I18n.t("workspaces.projects.destroy.trigger"))
    end

    it "opens a confirmation dialog explaining the action before archiving" do
      visit edit_workspace_project_path(project.workspace, project)
      click_button I18n.t("workspaces.projects.destroy.trigger")
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text(I18n.t("workspaces.projects.destroy.confirm"))
    end

    it "archives the project and redirects to the projects index on confirm" do
      visit edit_workspace_project_path(project.workspace, project)
      click_button I18n.t("workspaces.projects.destroy.trigger")
      within("dialog[open]") { click_button I18n.t("workspaces.projects.destroy.confirm_action") }

      expect(page).to have_current_path(workspace_projects_path(project.workspace))
      expect(page).to have_text(I18n.t("workspaces.projects.destroy.success"))
      expect(project.reload).to be_discarded
    end

    it "passes axe-core at WCAG 2.2 AAA with the dialog open, in light and dark modes" do
      visit edit_workspace_project_path(project.workspace, project)
      click_button I18n.t("workspaces.projects.destroy.trigger")
      expect(page).to have_css("dialog[open]")
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  context "as a project viewer (not the creator, no manage_workspace permission)" do
    let(:viewer) { create(:user) }

    before do
      create(:project_membership, :viewer, project: project, user: viewer)
      sign_in_via_form(viewer)
    end

    it "cannot reach the edit page at all (edit? defers to update?, creator-only)" do
      visit edit_workspace_project_path(project.workspace, project)
      expect(page).to have_current_path(workspace_path(project.workspace))
      expect(page).to have_text(I18n.t("errors.not_authorized"))
    end
  end
end
