require "rails_helper"

# Reshape 2b end-to-end: a brand-new visitor clicks a workspace join link
# (which doubles as the account-gate opener under :invite_only instance mode),
# registers, verifies their email, and lands in the workspace as Member.
#
# Threads through:
#   1. Workspaces::JoinsController#create unauthenticated → stash + redirect
#   2. SignupPolicy.allows_signup?(join_token:) → gate opens
#   3. RegistrationsController#create → parks pending_join_link_token on auth
#   4. Settings::ConnectedAccountsController#verify → claims via
#      Authentication#claim_pending_join_link! → workspace.admit
RSpec.describe "Flow B: new user signs up via workspace join link", type: :request do
  let(:owner)     { create(:user) }
  let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
  let!(:owner_role) {
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    }
  }
  let!(:member_role) {
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
      r.name = "Member"
      r.permissions = { manage_projects: true }
    }
  }
  let(:link) { create(:workspace_join_link, workspace: workspace, created_by: owner) }

  before do
    # Tight posture for Flow B: invite_only instance with open_link permitted.
    allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    workspace.memberships.create!(user: owner, role: owner_role)
  end

  it "stashes the join token, opens the signup gate, parks the token on the email auth, and admits on verification" do
    # 1. Unauthenticated visitor POSTs the join link → stash + redirect.
    post workspace_join_path(workspace, token: link.token)
    expect(session[:pending_join_token]).to eq(link.token)
    expect(response).to redirect_to(new_registration_path)

    # 2. The signup gate is open even under :invite_only because the join
    #    token in the session resolves to an active open-link workspace.
    get new_registration_path
    expect(response).to render_template(:new)

    # 3. Register. The new email authentication parks the join token.
    post registration_path, params: {
      user: {
        email_address: "newcomer@example.com",
        first_name: "New",
        last_name: "Comer",
        password: "SecureP@ssw0rd123!",
        password_confirmation: "SecureP@ssw0rd123!"
      }
    }
    new_user = User.find_by!(email_address: "newcomer@example.com")
    auth = new_user.authentications.email.first!
    expect(auth.pending_join_link_token).to eq(link.token)
    expect(session[:pending_join_token]).to be_nil

    # Not a member of the workspace yet — gated on email verification.
    expect(new_user.workspaces).not_to include(workspace)

    # 4. Verify the email. claim_pending_join_link! admits the user as Member.
    get verify_settings_connected_accounts_path(token: auth.generate_token_for(:email_verification))

    expect(new_user.reload.workspaces).to include(workspace)
    expect(workspace.memberships.find_by!(user: new_user).role.slug).to eq("member")
    expect(auth.reload.pending_join_link_token).to be_nil
  end
end
