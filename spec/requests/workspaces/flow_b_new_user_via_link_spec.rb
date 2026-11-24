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
  before do
    # Tight posture for Flow B: invite_only instance with open_link permitted.
    allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
    permit_open_join_links
  end

  def open_link_workspace_with_join_link
    owner = create(:user)
    workspace = create(:workspace, :open_link)
    create(:membership, :owner, user: owner, workspace: workspace)
    Role.system_default!("member")
    [ workspace, create(:workspace_join_link, workspace: workspace, created_by: owner) ]
  end

  it "stashes the join token, opens the signup gate, admits the user on magic-link signup" do
    workspace, link = open_link_workspace_with_join_link

    # 1. Unauthenticated visitor POSTs the join link → stash + redirect to sign-in.
    post workspace_join_path(workspace, token: link.plaintext_token)
    expect(session[:pending_join_token]).to eq(link.plaintext_token)
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

  # What Workspace::AdmissionError buys (#689): a fifth outcome added to #admit
  # is handled by the rescue that already handles the other three, instead of
  # 500ing a signup because nobody remembered to extend the list.
  context "when #admit raises an admission outcome this code predates" do
    before do
      stub_const("Workspace::FifthOutcome", Class.new(Workspace::AdmissionError))
      allow_any_instance_of(Workspace).to receive(:admit).and_raise(Workspace::FifthOutcome)
    end

    it "rolls the signup back and re-offers sign-in rather than erroring out" do
      workspace, link = open_link_workspace_with_join_link
      post workspace_join_path(workspace, token: link.plaintext_token)
      token = MagicLinkToken.create_for_email("newcomer@example.com")

      expect {
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "New", last_name: "Comer" }
        }
      }.not_to change(User, :count)

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("magic_link_callbacks.create.invalid"))
    end
  end
end
