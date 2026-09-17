require "rails_helper"

# Personal and org workspaces present the SAME sidebar shape. They used to
# diverge: orgs got a Settings nav item, personal workspaces got a "Customize"
# modal trigger holding name + logo — the same two fields the org Profile page
# already served at edit_workspace_path. One workspace, one shape, one route.
#
# Supersedes spec/requests/workspace_sidebar_settings_visibility_spec.rb, which
# asserted the divergence this file asserts is gone.
RSpec.describe "Workspace sidebar shape parity", type: :request do
  let(:user) { create(:user) }
  let(:org) { create(:workspace, name: "Acme") }
  let!(:org_membership) { create(:membership, :owner, user: user, workspace: org) }
  let(:personal) { user.personal_workspace }

  before { sign_in(user) }

  def sidebar_items(path)
    get path
    Nokogiri::HTML(response.body)
      .css("aside[aria-label] ul li a")
      .map { |a| [ a.text.strip, a["href"] ] }
  end

  it "offers Settings on a personal workspace, pointing at the same route as an org's" do
    personal_settings = sidebar_items(workspace_path(personal)).find { |label, _| label == "Settings" }
    org_settings = sidebar_items(workspace_path(org)).find { |label, _| label == "Settings" }

    expect(personal_settings).not_to be_nil, "personal workspace sidebar has no Settings item"
    expect(personal_settings.last).to eq(edit_workspace_path(personal))
    expect(org_settings.last).to eq(edit_workspace_path(org))
  end

  it "gives both workspace kinds the same sidebar labels in the same order" do
    expect(sidebar_items(workspace_path(personal)).map(&:first))
      .to eq(sidebar_items(workspace_path(org)).map(&:first))
  end

  it "no longer renders a Customize modal on a personal workspace" do
    get workspace_path(personal)

    expect(Nokogiri::HTML(response.body).at_css("#workspace-customize")).to be_nil
  end
end
