require "rails_helper"

# Ported from spec/system/workspaces/membership_touch_spec.rb (#854): the
# touch is WorkspaceScoped's before_action `update_all` — pure server-side,
# so the browser proved nothing the request layer doesn't, at ~176× the cost.
# Assertions are the system spec's, plus the response status it never checked.
RSpec.describe "Membership last_accessed_at touch", type: :request do
  let(:user) { create(:user) }
  let(:workspace_a) { create(:workspace, name: "Alpha") }
  let(:workspace_b) { create(:workspace, name: "Beta") }
  let!(:membership_a) { create(:membership, :owner, user: user, workspace: workspace_a) }
  let!(:membership_b) { create(:membership, :owner, user: user, workspace: workspace_b) }

  before { sign_in(user) }

  it "touches the visited workspace's membership and no other" do
    expect(membership_a.last_accessed_at).to be_nil
    expect(membership_b.last_accessed_at).to be_nil

    get workspace_path(workspace_a)
    expect(response).to have_http_status(:ok)
    expect(membership_a.reload.last_accessed_at).to be_within(5.seconds).of(Time.current)
    expect(membership_b.reload.last_accessed_at).to be_nil

    a_at_first_visit = membership_a.last_accessed_at
    travel 2.seconds

    get workspace_path(workspace_b)
    expect(response).to have_http_status(:ok)
    expect(membership_a.reload.last_accessed_at).to eq(a_at_first_visit)
    expect(membership_b.reload.last_accessed_at).to be_within(5.seconds).of(Time.current)
  end
end
