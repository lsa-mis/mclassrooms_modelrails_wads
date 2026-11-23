require "rails_helper"

RSpec.describe "Locked workspace gate", type: :request do
  def locked_workspace_of_signed_in_owner
    user = create(:user)
    workspace = create(:workspace)
    sign_in_as_owner_of(workspace, user: user)
    workspace.suspend!
    workspace
  end

  it "redirects workspace pages to the index with the locked notice" do
    workspace = locked_workspace_of_signed_in_owner
    get workspace_path(workspace)
    expect(response).to redirect_to(workspaces_path)
    expect(flash[:alert]).to eq(I18n.t("workspaces.locked_notice"))
  end

  it "gates nested workspace-scoped controllers too" do
    workspace = locked_workspace_of_signed_in_owner
    get workspace_members_path(workspace)
    expect(response).to redirect_to(workspaces_path)
  end

  # #688: the gate must hold for mutations, not just reads — the model-level
  # suspension raises stay HTTP-unreachable precisely because this
  # before_action fires first; this example is what proves that. (Fork: the
  # template proved it on projects#create; this fork's workspace-scoped
  # mutation is the member-role update.)
  it "gates a mutating action on a locked workspace (the model raise stays HTTP-unreachable)" do
    workspace = locked_workspace_of_signed_in_owner
    member = create(:membership, workspace: workspace)
    patch workspace_member_path(workspace, member),
      params: { membership: { role_id: member.role_id } }
    expect(response).to redirect_to(workspaces_path)
    expect(flash[:alert]).to eq(I18n.t("workspaces.locked_notice"))
  end

  it "renders the index fine with a locked workspace present (nil-gate regression)" do
    locked_workspace_of_signed_in_owner
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end

  it "blocks archiving (gate runs before the action)" do
    workspace = locked_workspace_of_signed_in_owner
    post workspace_archival_path(workspace)
    expect(response).to redirect_to(workspaces_path)
    expect(workspace.reload).not_to be_archived
  end

  # JoinsController skips WorkspaceScoped, so the lock is enforced separately;
  # outsiders get invalid_or_revoked, not locked_notice (privacy decision).
  describe "join links on a locked workspace" do
    before { permit_open_join_links }

    def locked_join_link
      locked_workspace = create(:workspace, :open_link, name: "Locked Co")
      owner = create(:user)
      create(:membership, :owner, user: owner, workspace: locked_workspace)
      locked_workspace.suspend!
      create(:workspace_join_link, workspace: locked_workspace, created_by: owner)
    end

    it "redirects the GET join page with the invalid_or_revoked flash (no locked disclosure)" do
      link = locked_join_link
      locked_workspace = link.workspace
      sign_in(create(:user))
      get workspace_join_path(locked_workspace, token: link.plaintext_token)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
    end

    it "does not admit a new member on POST, and redirects with the invalid_or_revoked flash" do
      link = locked_join_link
      locked_workspace = link.workspace
      sign_in(create(:user))
      expect {
        post workspace_join_path(locked_workspace, token: link.plaintext_token)
      }.not_to change(locked_workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
    end
  end

  # Invitation#accept! is the single acceptance funnel, so guarding it closes
  # every path; invitees get acceptance_failed, not locked_notice (privacy).
  describe "invitations to a locked workspace" do
    def workspace_with_owner
      locked_workspace = create(:workspace, name: "Locked Co")
      owner = create(:user)
      create(:membership, :owner, user: owner, workspace: locked_workspace)
      [ locked_workspace, owner ]
    end

    it "does not admit a member via a pending WORKSPACE invitation, and redirects with the existing acceptance_failed copy" do
      locked_workspace, owner = workspace_with_owner
      invitee = create(:user)
      viewer_role = Role.system_default!("viewer")
      invitation = create(:invitation, invitable: locked_workspace, email: invitee.email_address, role: viewer_role, invited_by: owner)
      locked_workspace.suspend!
      sign_in(invitee)

      expect {
        post accept_invitation_path(token: invitation.token)
      }.not_to change(Membership, :count)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_accepts.create.acceptance_failed"))
    end
  end
end
