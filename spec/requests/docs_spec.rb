require "rails_helper"

RSpec.describe "Documentation", type: :request do
  it "GET /docs renders successfully" do
    get "/docs"
    expect(response).to have_http_status(:ok)
  end

  # #734: the docs search renders through UI::SearchInput — a real search
  # control with an accessible name (the old input was type=text named only
  # by its placeholder) and the docs-search Stimulus wiring intact.
  it "renders the search box as a labelled search input with its Stimulus wiring" do
    get "/docs"
    page = Capybara.string(response.body)
    input = page.find("input[type='search'][data-docs-search-target='input']", visible: :all)
    expect(input["aria-label"]).to be_present
    expect(input["data-action"]).to include("docs-search#search")
  end
end
