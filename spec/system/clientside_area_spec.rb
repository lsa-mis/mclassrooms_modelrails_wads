# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Client area", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:client) { create(:user) }
  let(:access) { create(:client_access, user: client) }
  let(:project) { access.project }
  let(:shared_resource) do
    create(:resource,
      project: project,
      status: "published",
      shared_with_client: true,
      title: "Shared Doc",
      resourceable: create(:document, body: "This is the resource body content for client review."))
  end

  before do
    access
    shared_resource
    create(:resource, project: project, status: "published", shared_with_client: false, title: "Internal Doc")
    sign_in_via_form(client)
  end

  it "shows a client only the shared items, AAA in both themes" do
    visit clientside_project_path(project)
    expect(page).to have_link("Shared Doc")
    expect(page).to have_no_link("Internal Doc")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true), axe_violations_in_both_themes(axe_options).join("\n")
  end

  it "renders the resource show page with title and body, AAA in both themes" do
    visit clientside_project_resource_path(project, shared_resource)
    expect(page).to have_css("h1", text: "Shared Doc")
    expect(page).to have_text("This is the resource body content for client review.")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true), axe_violations_in_both_themes(axe_options).join("\n")
  end
end
