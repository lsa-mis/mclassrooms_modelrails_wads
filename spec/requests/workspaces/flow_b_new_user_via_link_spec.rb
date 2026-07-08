require "rails_helper"

# Flow B end-to-end: a brand-new visitor clicks a workspace join link,
# signs up via magic-link, and lands in the workspace as Member.
#
# Threads through:
#   1. Workspaces::JoinsController#create unauthenticated → stash + redirect
#   2. SignupPolicy.allows_signup?(join_token:) → gate opens
#   3. MagicLinkCallbacksController#create → accept_pending_join_link! via Signupable
#   4. User is a member immediately (magic-link signup is atomic, no deferred verify)
RSpec.describe "Flow B: new user signs up via workspace join link", type: :request do
  let(:owner)     { create(:user) }
  let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
  let!(:owner_role) {
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_settings: true }
    }
  }
  let!(:member_role) {
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
      r.name = "Member"
      r.permissions = {}
    }
  }
  let(:link) { create(:workspace_join_link, workspace: workspace, created_by: owner) }

  before do
    # Tight posture for Flow B: invite_only instance with open_link permitted.
    allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    workspace.memberships.create!(user: owner, role: owner_role)
  end

  it "stashes the join token, opens the signup gate, admits the user on magic-link signup" do
    # 1. Unauthenticated visitor POSTs the join link → stash + redirect to sign-in.
    post workspace_join_path(workspace, token: link.token)
    expect(session[:pending_join_token]).to eq(link.token)
    expect(response).to redirect_to(new_session_path)

    # 2. The signup gate is open even under :invite_only because the join
    #    token in the session resolves to an active open-link workspace.
    get new_session_path
    expect(response).to have_http_status(:ok)

    # 3. Sign up via magic-link. Signupable#accept_pending_join_link! admits
    #    the user atomically during magic-link callback (no separate verify step).
    token = MagicLinkToken.create_for_email("newcomer@example.com")
    post magic_link_callback_path(token: token), params: {
      user: { first_name: "New", last_name: "Comer" }
    }

    new_user = User.find_by!(email_address: "newcomer@example.com")
    auth = new_user.authentications.email.first!

    # 4. Magic-link signup is atomic: user is a member immediately.
    expect(new_user.workspaces).to include(workspace)
    expect(workspace.memberships.find_by!(user: new_user).role.slug).to eq("member")
    expect(session[:pending_join_token]).to be_nil

    # The email auth is verified immediately (magic-link proves email ownership).
    expect(auth.verified_at).to be_present
  end
end
