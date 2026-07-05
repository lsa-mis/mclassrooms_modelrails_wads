require "rails_helper"

# The workspace identity (name/logo) must lead the mobile section-nav strip on
# the Overview — identity before navigation (Adam + Steve review). Asserted by
# DOM order of the two stable ids.
RSpec.describe "Workspace overview reading order", type: :request do
  it "renders the workspace name heading before the section-nav strip" do
    user = create(:user)
    workspace = create(:workspace, personal: false)
    create(:membership, :owner, user: user, workspace: workspace)
    sign_in(user)

    get workspace_path(workspace)

    body = response.body
    name_pos = body.index("workspace-name-heading")
    strip_pos = body.index("section-nav-strip-heading")
    expect(name_pos).to be_present
    expect(strip_pos).to be_present
    expect(name_pos).to be < strip_pos
  end
end
