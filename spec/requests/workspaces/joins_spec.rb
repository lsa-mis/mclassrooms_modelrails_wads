require "rails_helper"

RSpec.describe "Workspaces::Joins (Flow A: authenticated user joins via link)", type: :request do
  # Pinned apostrophe name: Faker's intermittently produced HTML-special chars, which broke
  # the raw response.body match below. Keeps the escaping path always exercised.
  def open_workspace_with_owner
    workspace = create(:workspace, :open_link, name: "O'Brien Logistics")
    [ workspace, create(:membership, :owner, workspace: workspace).user ]
  end

  def signed_in_newcomer
    create(:user).tap { |newcomer| sign_in(newcomer) }
  end

  before { permit_open_join_links }

  describe "POST /workspaces/:slug/joins/:token" do
    it "admits the user as a Member and redirects to the workspace" do
      workspace, owner = open_workspace_with_owner
      role = Role.system_default!("member")
      newcomer = signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)

      expect {
        post workspace_join_path(workspace, token: link.plaintext_token)
      }.to change(workspace.memberships, :count).by(1)

      membership = workspace.memberships.find_by!(user: newcomer)
      expect(membership.role).to eq(role)
      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:notice]).to eq(I18n.t("workspaces.joins.create.joined", workspace_name: workspace.name))
    end

    # A revoke inside the last guard is refused by admit's re-check (#1061).
    it "refuses a link revoked between the posture check and the write" do
      workspace, owner = open_workspace_with_owner
      Role.system_default!("member")
      signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      allow_any_instance_of(Workspace).to receive(:accepting_open_joins?).and_wrap_original do |original|
        original.call.tap { |open| link.revoke! if open }
      end

      expect {
        post workspace_join_path(workspace, token: link.plaintext_token)
      }.not_to change(workspace.memberships, :count)
    end

    # Nobody is notified about their own action: the joiner is the actor here,
    # so member-added goes to the owner only and the joiner is oriented by
    # WorkspaceJoinedNotifier instead.
    it "leaves the joiner out of member-added, notifies the owner, and orients the joiner" do
      workspace, owner = open_workspace_with_owner
      Role.system_default!("member")
      newcomer = signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      Noticed::Notification.delete_all

      post workspace_join_path(workspace, token: link.plaintext_token)

      member_added = Noticed::Notification
        .where(type: "WorkspaceMemberAddedNotifier::Notification").map(&:recipient)
      expect(member_added).to contain_exactly(owner)
      expect(
        Noticed::Notification.where(recipient: newcomer, type: "WorkspaceJoinedNotifier::Notification").count
      ).to eq 1
    end

    it "rejects a revoked link" do
      workspace, owner = open_workspace_with_owner
      Role.system_default!("member")
      signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      link.revoke!
      expect {
        post workspace_join_path(workspace, token: link.plaintext_token)
      }.not_to change(workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
    end

    it "rejects an expired (but unrevoked) link with the same neutral error" do
      workspace, owner = open_workspace_with_owner
      Role.system_default!("member")
      signed_in_newcomer
      token = create(:workspace_join_link, workspace: workspace, created_by: owner).plaintext_token
      travel_to 8.days.from_now do
        expect {
          post workspace_join_path(workspace, token: token)
        }.not_to change(workspace.memberships, :count)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
      end
    end

    it "rejects when the workspace's join_policy is not open_link" do
      workspace, owner = open_workspace_with_owner
      Role.system_default!("member")
      signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      workspace.update!(join_policy: "invite")
      expect {
        post workspace_join_path(workspace, token: link.plaintext_token)
      }.not_to change(workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
    end

    it "rejects when the instance allowlist excludes :open_link" do
      workspace, owner = open_workspace_with_owner
      Role.system_default!("member")
      signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      expect {
        post workspace_join_path(workspace, token: link.plaintext_token)
      }.not_to change(workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
    end

    it "surfaces a clean message when the workspace is at capacity" do
      workspace, owner = open_workspace_with_owner
      Role.system_default!("member")
      newcomer = signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      workspace.update!(max_members: 1)  # owner already fills capacity
      post workspace_join_path(workspace, token: link.plaintext_token)
      expect(workspace.memberships.find_by(user: newcomer)).to be_nil
      # A generic i18n message, never the raw model validation string.
      expect(flash[:alert]).to eq(I18n.t("workspaces.joins.create.could_not_join", workspace_name: workspace.name))
      expect(flash[:alert]).not_to match(/capacity|max_members/i)
    end

    it "redirects gracefully when the user is already a member" do
      workspace, owner = open_workspace_with_owner
      newcomer = signed_in_newcomer
      create(:membership, user: newcomer, workspace: workspace)
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      post workspace_join_path(workspace, token: link.plaintext_token)
      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:notice]).to eq(I18n.t("workspaces.joins.create.already_member", workspace_name: workspace.name))
    end

    it "returns the same neutral error for invalid + unauthorized cases (no info leak)" do
      workspace, owner = open_workspace_with_owner
      Role.system_default!("member")
      signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      # Confirms that "link doesn't exist" and "policy isn't open_link" surface
      # the same alert — don't reveal whether a specific workspace allows joins.
      workspace.update!(join_policy: "invite")
      post workspace_join_path(workspace, token: link.plaintext_token)
      no_policy_alert = flash[:alert]

      post workspace_join_path(workspace, token: "totally-fake-token")
      no_link_alert = flash[:alert]

      expect(no_policy_alert).to be_present
      expect(no_link_alert).to eq(no_policy_alert)
    end
  end

  describe "GET /workspaces/:slug/joins/:token" do
    it "renders a confirmation page for a valid active link" do
      workspace, owner = open_workspace_with_owner
      signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      get workspace_join_path(workspace, token: link.plaintext_token)
      expect(response).to have_http_status(:ok)
      expect(Capybara.string(response.body)).to have_text(workspace.name)
    end

    it "redirects with an error for a revoked link" do
      workspace, owner = open_workspace_with_owner
      signed_in_newcomer
      link = create(:workspace_join_link, workspace: workspace, created_by: owner)
      link.revoke!
      get workspace_join_path(workspace, token: link.plaintext_token)
      expect(response).to redirect_to(root_path)
    end

    it "redirects with the same neutral error for an expired (but unrevoked) link" do
      workspace, owner = open_workspace_with_owner
      signed_in_newcomer
      token = create(:workspace_join_link, workspace: workspace, created_by: owner).plaintext_token
      travel_to 8.days.from_now do
        get workspace_join_path(workspace, token: token)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
      end
    end
  end
end

# Reshape 2b: unauthenticated branch. Top-level describe so it doesn't
# inherit the Flow A spec's `sign_in(newcomer)` before-hook. Visiting a
# valid join link without an account stashes the token in the session and
# routes the visitor through the registration flow. After email
# verification, claim_pending_join_link! admits them to the workspace.
RSpec.describe "Workspaces::Joins (Flow B: unauthenticated user via link)", type: :request do
  def open_workspace_with_owner
    workspace = create(:workspace, :open_link, name: "O'Brien Logistics")
    [ workspace, create(:membership, :owner, workspace: workspace).user ]
  end

  before { permit_open_join_links }

  it "POST stashes the join token in the session and redirects to sign-in" do
    workspace, owner = open_workspace_with_owner
    link = create(:workspace_join_link, workspace: workspace, created_by: owner)
    post workspace_join_path(workspace, token: link.plaintext_token)

    expect(session[:pending_join_token]).to eq(link.plaintext_token)
    expect(response).to redirect_to(new_session_path)
    expect(flash[:notice]).to eq(I18n.t("workspaces.joins.create.register_first", workspace_name: workspace.name))
  end

  it "POST with a revoked link uses the neutral error (no session stash, no info leak)" do
    workspace, owner = open_workspace_with_owner
    link = create(:workspace_join_link, workspace: workspace, created_by: owner)
    link.revoke!
    post workspace_join_path(workspace, token: link.plaintext_token)

    expect(session[:pending_join_token]).to be_nil
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
  end

  it "GET renders the confirmation page without requiring auth" do
    workspace, owner = open_workspace_with_owner
    link = create(:workspace_join_link, workspace: workspace, created_by: owner)
    get workspace_join_path(workspace, token: link.plaintext_token)
    expect(response).to have_http_status(:ok)
    expect(Capybara.string(response.body)).to have_text(workspace.name)
  end
end
