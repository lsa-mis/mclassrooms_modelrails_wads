require "rails_helper"

RSpec.describe "Workspace shell section-nav strip (mobile)", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, personal: false) }
  before do
    create(:membership, :owner, user: user, workspace: workspace)
    sign_in_via_form(user)
    cdp_resize(375, 667)
  end

  it "shows Overview/Settings as an in-page strip with the current page marked" do
    visit workspace_path(workspace)
    expect(page).to have_css("nav[aria-labelledby='section-nav-strip-heading'] a[aria-current='page']",
                             text: I18n.t("workspaces.sidebar.overview"))
  end
end
