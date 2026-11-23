require "rails_helper"

RSpec.describe "Standalone workspace back-link is gone", type: :request do
  it "no longer renders the back-to-workspace nav on a settings page" do
    workspace = create(:workspace, name: "Acme")
    sign_in_as_owner_of(workspace)

    get edit_workspace_settings_path(workspace)
    doc = Nokogiri::HTML(response.body)
    back_links = doc.css("nav a").select { |a| a["href"] == workspace_path(workspace) && a["id"] != "workspace-name-heading" }
    # Only the identity-bar name-link and breadcrumb crumb may point to the Overview.
    expect(back_links.map { |a| a.text.strip }).not_to include(a_string_matching(/back to/i))
  end
end
