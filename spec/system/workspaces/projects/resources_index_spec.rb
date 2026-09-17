# frozen_string_literal: true

require "rails_helper"

# The pointer resting on a row is a state a visitor reaches. A static
# list_group_item highlights on hover unless told not to, and the title link's
# text-interactive over that highlight is below AAA — so the row is audited
# hovered, not only at rest.
RSpec.describe "Resources index", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    create(:resource, project: project, title: "Kickoff notes")
    sign_in_via_form(user)
  end

  it "passes axe AAA in both themes with the pointer resting on a resource row" do
    visit workspace_project_resources_path(workspace, project)
    expect(page).to have_link("Kickoff notes")

    page.find("li", text: "Kickoff notes").hover
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
