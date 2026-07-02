require "rails_helper"

RSpec.describe "Workspace settings danger zone", type: :system do
  let(:owner) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Inc") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before { create(:membership, :owner, user: owner, workspace: workspace) }

  context "as an owner" do
    before { sign_in_via_form(owner) }

    it "shows an Archive workspace trigger on the Settings page" do
      visit edit_workspace_settings_path(workspace)
      expect(page).to have_button(I18n.t("workspaces.destroy.trigger"))
    end

    it "opens a confirmation dialog explaining the action before archiving" do
      visit edit_workspace_settings_path(workspace)
      click_button I18n.t("workspaces.destroy.trigger")
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text(I18n.t("workspaces.destroy.confirm"))
    end

    it "archives the workspace and redirects to the workspaces index on confirm" do
      visit edit_workspace_settings_path(workspace)
      click_button I18n.t("workspaces.destroy.trigger")
      within("dialog[open]") { click_button I18n.t("workspaces.destroy.confirm_action") }

      expect(page).to have_current_path(workspaces_path)
      expect(page).to have_text(I18n.t("workspaces.destroy.success"))
      expect(workspace.reload).to be_discarded
    end

    it "passes axe-core at WCAG 2.2 AAA with the dialog open, in light and dark modes" do
      visit edit_workspace_settings_path(workspace)
      click_button I18n.t("workspaces.destroy.trigger")
      expect(page).to have_css("dialog[open]")
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  context "as a plain member (no manage_settings permission)" do
    let(:member) { create(:user) }

    before do
      create(:membership, user: member, workspace: workspace)
      sign_in_via_form(member)
    end

    it "cannot reach the Settings page at all (edit? requires manage_settings)" do
      visit edit_workspace_settings_path(workspace)
      expect(page).to have_current_path(workspace_path(workspace))
      expect(page).to have_text(I18n.t("errors.not_authorized"))
    end
  end
end
