require "rails_helper"

# The client-side filter on the workspaces index only appears once the
# "Other workspaces" list is long enough to be worth scanning (>= 8).
RSpec.describe "Workspaces index filter", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  it "renders the filter + its controller once the other list is long (>= 8)" do
    8.times { create(:membership, :owner, user: user, workspace: create(:workspace)) }

    get workspaces_path

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("section[data-controller='workspace-filter']")).not_to be_nil
    expect(doc.at_css("input#workspace-filter[type='search'][data-workspace-filter-target='input']")).not_to be_nil
    expect(doc.at_css("p[data-workspace-filter-target='empty'][hidden]")).not_to be_nil
  end

  it "omits the filter for a short list" do
    2.times { create(:membership, :owner, user: user, workspace: create(:workspace)) }

    get workspaces_path

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("input#workspace-filter")).to be_nil
    expect(doc.at_css("[data-controller='workspace-filter']")).to be_nil
  end
end
