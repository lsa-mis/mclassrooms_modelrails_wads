require "rails_helper"

# The docs breadcrumb is the host's override of the markdowndocs gem partial;
# it renders through UI::Breadcrumb (W1 PR-F). Discriminators vs the old
# hand-rolled markup: slash separators (was chevron SVGs) and focus-ring links.
RSpec.describe "Docs breadcrumb", type: :request do
  it "renders through UI::Breadcrumb with slash separators and a current page" do
    get "/docs/developer/presets"
    expect(response).to have_http_status(:ok)

    nav = Capybara.string(response.body).find("nav[aria-label='Breadcrumb']")
    expect(nav[:class]).to include("mb-6")
    expect(nav).to have_css("ol a.focus-ring", count: 2)
    expect(nav).to have_link("Docs", href: "/docs/")
    expect(nav).to have_link("Presets (Tenancy)", href: "/docs/#presets-tenancy")
    # The current item is a bare span carrying aria-current, never a link.
    expect(nav).to have_css("span[aria-current='page']", text: "App Presets")
    expect(nav).to have_no_css("a[aria-current]")
    expect(nav).to have_css("span[aria-hidden='true']", text: "/", count: 2)
    expect(nav).to have_no_css("svg")
  end
end
