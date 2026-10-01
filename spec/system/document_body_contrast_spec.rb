# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Document body contrast", type: :system do
  let(:user) { create(:user) }
  let(:body) { "<p>See the <a href='https://example.com/agenda'>agenda</a> first.</p>" }

  before { sign_in_via_form(user) }

  def visit_document_in(workspace)
    project = create(:project, workspace: workspace, created_by: user)
    resource = create(:resource, project: project, created_by: user,
                                 resourceable: create(:document, body: body))
    visit workspace_project_resource_path(workspace, project, resource)
    expect(page).to have_link("agenda")
  end

  it "keeps a link in the body AAA in a personal workspace, both themes" do
    visit_document_in(user.workspaces.sole)

    expect(page).to have_css("main[data-workspace-kind='personal']")
    expect_aaa_in_both_themes
  end

  it "keeps a link in the body AAA in an organization workspace, both themes" do
    workspace = create(:workspace)
    create(:membership, :owner, user: user, workspace: workspace)
    visit_document_in(workspace)

    expect(page).to have_css("main[data-workspace-branded]")
    expect_aaa_in_both_themes
  end
end
