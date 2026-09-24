require "rails_helper"

# shared/_sortable_header used to hard-code data-turbo-frame="members_results",
# which made the partial unusable on any page without that frame (#1164). The
# members page now passes its frame explicitly; a caller passing nothing gets a
# plain link that targets whatever frame encloses it.
RSpec.describe "Sortable header frame local", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }

  before do
    create(:membership, :owner, user: user, workspace: workspace)
    sign_in(user)
  end

  it "targets the members frame because the members page passes frame: explicitly" do
    get workspace_members_path(workspace)
    link = Capybara.string(response.body).first(:link, I18n.t("workspaces.members.index.name"))
    expect(link["data-turbo-frame"]).to eq("members_results")
  end

  # A sortable header has to LOOK sortable before anyone touches it. At rest the
  # link carried the same size, weight and colour as a plain <th>, so the only
  # cue was hover, which no phone has, or the direction arrow, which renders on
  # the sorted column alone. Assistive tech could already tell the two kinds
  # apart from aria-sort; a sighted user could not.
  it "carries a resting indicator on every sortable header and a directional one on the sorted column" do
    get workspace_members_path(workspace, sort: "name", direction: "asc")
    html = Capybara.string(response.body)

    expect(html.find("th[aria-sort='ascending']")).to have_css("svg[data-sort-indicator='ascending']")

    resting = html.all("th[aria-sort='none']")
    expect(resting.size).to eq(2)
    resting.each { |header| expect(header).to have_css("svg[data-sort-indicator='none']") }

    # A header that does not sort stays bare: the indicator is the whole
    # difference between the two kinds.
    expect(html.all("thead th:not([aria-sort]) svg")).to be_empty
  end

  it "keeps the sort state on the th, not in the glyph" do
    html = ApplicationController.render(
      partial: "shared/sortable_header",
      locals: { title: "When", column: "created_at", current_sort: nil, current_direction: nil,
                url: ->(p) { "/x?#{p.to_query}" } }
    )
    indicator = Capybara.string(html).find("svg[data-sort-indicator]", visible: :all)
    expect(indicator[:"aria-hidden"]).to eq("true")
    expect(indicator[:role]).to be_nil
  end

  it "renders no frame target when the caller passes none" do
    html = ApplicationController.render(
      partial: "shared/sortable_header",
      locals: { title: "When", column: "created_at", current_sort: nil, current_direction: nil,
                url: ->(p) { "/x?#{p.to_query}" } }
    )
    link = Capybara.string(html).first(:link, "When")
    expect(link["data-turbo-frame"]).to be_nil
    expect(Capybara.string(html)).to have_css('th[scope="col"][aria-sort="none"]')
  end
end
