# frozen_string_literal: true

require "rails_helper"

# W1-6 (#729, PR-B): the resource forms bypassed UI::FormBuilder — native
# `required` let the browser block an empty submit with a transient bubble,
# so the server-rendered error path (error summary + inline errors) every
# sibling form uses could never render. These examples exercise that path
# end-to-end; they FAIL on the pre-migration markup because the bubble
# blocks the submit and no request reaches the server.
RSpec.describe "Resource forms", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }

  before do
    create(:project_membership, :creator, project: project, user: user)
    sign_in_via_form(user)
  end

  it "renders the error summary when a new document is submitted without a title" do
    visit new_workspace_project_resource_path(workspace, project)

    click_button I18n.t("workspaces.projects.resources.new.submit")

    within("[role='alert']") do
      expect(page).to have_link("Title can't be blank", href: "#resource_title")
    end
  end

  it "creates a document from a valid title-only submit" do
    visit new_workspace_project_resource_path(workspace, project)

    fill_in I18n.t("workspaces.projects.resources.new.title_label"), with: "Kickoff notes"
    click_button I18n.t("workspaces.projects.resources.new.submit")

    expect(page).to have_text(I18n.t("workspaces.projects.resources.create.success"))
    expect(page).to have_text("Kickoff notes")
  end

  describe "editing" do
    let!(:resource) do
      create(:resource, project: project, created_by: user, title: "Original title")
    end

    it "renders the error summary when the title is cleared" do
      visit edit_workspace_project_resource_path(workspace, project, resource)

      fill_in I18n.t("workspaces.projects.resources.edit.title_label"), with: ""
      click_button I18n.t("workspaces.projects.resources.edit.submit")

      within("[role='alert']") do
        expect(page).to have_link("Title can't be blank", href: "#resource_title")
      end
    end
  end
end
