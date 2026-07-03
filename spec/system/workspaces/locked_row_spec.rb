require "rails_helper"

RSpec.describe "Locked workspace row", type: :system do
  let(:owner) { create(:user) }
  let(:workspace) { create(:workspace, name: "Frozen Co") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    workspace.suspend!
    sign_in_via_form(owner)
  end

  it "renders the locked notice with a Contact support action instead of workspace actions" do
    visit workspaces_path
    within("[data-test='locked-workspace-row']") do
      expect(page).to have_text(I18n.t("workspaces.locked_row.heading"))
      expect(page).to have_text(I18n.t("workspaces.locked_row.body", name: "Frozen Co"))
      expect(page).to have_link(I18n.t("workspaces.locked_row.contact"), href: contact_path)
    end
    # The internal word must never render
    expect(page).to have_no_text(/suspended/i)
  end

  it "passes axe AAA in both themes with a locked workspace present" do
    visit workspaces_path
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
