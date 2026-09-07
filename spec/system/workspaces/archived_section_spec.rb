require "rails_helper"

RSpec.describe "Workspaces index archived section", type: :system do
  let(:owner) { create(:user) }
  let(:active_workspace) { create(:workspace, name: "Active Co") }
  let(:archived_workspace) { create(:workspace, name: "Dusty Co") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    create(:membership, :owner, user: owner, workspace: active_workspace)
    create(:membership, :owner, user: owner, workspace: archived_workspace)
    archived_workspace.archive!
    sign_in_via_form(owner)
  end

  it "moves archived workspaces out of the main list into the Archived section" do
    visit workspaces_path
    within("[data-test='archived-workspaces']") do
      expect(page).to have_text("Dusty Co")
    end
    expect(page).to have_no_css("[data-test='current-workspace-row'] li", text: "Dusty Co")
    expect(page).to have_no_css("[data-test='other-workspaces-list'] li", text: "Dusty Co")
  end

  it "restores from the Archived section" do
    visit workspaces_path
    within("[data-test='archived-workspaces']") { click_button I18n.t("lifecycle.restore") }
    expect(page).to have_text(I18n.t("workspaces.archivals.destroy.success"))
    expect(archived_workspace.reload).not_to be_archived
  end

  it "keeps the archived workspace's own pages reachable, with a Restore banner" do
    visit workspace_path(archived_workspace)
    within("[data-test='archived-banner']") do
      expect(page).to have_text(I18n.t("workspaces.archived_banner"))
      click_button I18n.t("lifecycle.restore")
    end
    expect(page).to have_text(I18n.t("workspaces.archivals.destroy.success"))
    expect(archived_workspace.reload).not_to be_archived
  end

  it "passes axe AAA in both themes with an archived workspace present" do
    visit workspaces_path
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
