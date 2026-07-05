require "rails_helper"

# Workspace Profile destination — the new home for identity edits (name,
# logo, primary_color) after the settings hub route consolidation. Posts to
# workspaces#update; gated by Workspaces::ProfilePolicy (manage_settings).
RSpec.describe "Workspace Profile destination", type: :system do
  let(:owner) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Corp") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    sign_in_via_form(owner)
  end

  it "renders the Profile H1, disambiguated by the persistent identity bar" do
    visit edit_workspace_path(workspace)
    expect(page).to have_css("h1", text: "Profile")
    expect(page).to have_css("#workspace-name-heading", text: workspace.name)
  end

  it "renders the Profile description" do
    visit edit_workspace_path(workspace)
    expect(page).to have_text(I18n.t("settings.pages.workspace_profile.description"))
  end

  it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
    visit edit_workspace_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
