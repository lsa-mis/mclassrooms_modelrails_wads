require "rails_helper"

RSpec.describe "Workspace settings danger zone", type: :system do
  let(:owner) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Inc") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before { create(:membership, :owner, user: owner, workspace: workspace) }

  context "as an owner" do
    before { sign_in_via_form(owner) }

    it "archives (not deletes) via the Archive action" do
      visit edit_workspace_settings_path(workspace)
      click_button I18n.t("workspaces.archive.trigger")
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text(I18n.t("workspaces.archive.confirm"))

      within("dialog[open]") { click_button I18n.t("workspaces.archive.confirm_action") }

      expect(page).to have_current_path(workspaces_path)
      expect(page).to have_text(I18n.t("workspaces.archive.success"))
      expect(workspace.reload).to be_archived
      expect(workspace.reload).not_to be_discarded
    end

    it "requires typing the workspace name before Delete enables" do
      visit edit_workspace_settings_path(workspace)
      click_button I18n.t("workspaces.destroy.trigger")

      within("dialog[open]") do
        expect(page).to have_button(I18n.t("workspaces.destroy.confirm_action"), disabled: true)
        fill_in I18n.t("modals.confirm_input_label", name: workspace.name), with: "wrong name"
        expect(page).to have_button(I18n.t("workspaces.destroy.confirm_action"), disabled: true)
        fill_in I18n.t("modals.confirm_input_label", name: workspace.name), with: "  Acme Inc  "
        expect(page).to have_button(I18n.t("workspaces.destroy.confirm_action"), disabled: false)
        click_button I18n.t("workspaces.destroy.confirm_action")
      end

      expect(page).to have_current_path(workspaces_path)
      expect(workspace.reload).to be_discarded
    end

    it "passes axe AAA with the archive dialog open, both themes" do
      visit edit_workspace_settings_path(workspace)
      click_button I18n.t("workspaces.archive.trigger")
      expect(page).to have_css("dialog[open]")
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    it "passes axe AAA with the delete dialog open, both themes" do
      visit edit_workspace_settings_path(workspace)
      click_button I18n.t("workspaces.destroy.trigger")
      expect(page).to have_css("dialog[open]")
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  context "on a personal (home) workspace" do
    let(:home) { create(:workspace, personal: true) }

    before do
      create(:membership, :owner, user: owner, workspace: home)
      sign_in_via_form(owner)
    end

    it "shows no Archive or Delete controls (home workspaces are lifecycle-exempt)" do
      visit edit_workspace_settings_path(home)
      expect(page).to have_no_button(I18n.t("workspaces.archive.trigger"))
      expect(page).to have_no_button(I18n.t("workspaces.destroy.trigger"))
    end
  end

  context "as a plain member (no manage_settings permission)" do
    let(:member) { create(:user) }

    before do
      create(:membership, user: member, workspace: workspace)
      sign_in_via_form(member)
    end

    it "cannot reach the Settings page at all" do
      visit edit_workspace_settings_path(workspace)
      expect(page).to have_current_path(workspace_path(workspace))
      expect(page).to have_text(I18n.t("errors.not_authorized"))
    end
  end
end
