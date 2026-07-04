require "rails_helper"

RSpec.describe "Workspaces::Joins (Flow A: authenticated user joins via link)", type: :request do
  # Deterministic name with an apostrophe: Faker::Company.name intermittently
  # produces HTML-special chars (e.g. "O'Kon" -> "O&#39;Kon"), which broke the
  # raw response.body string match below. Pin it so the escaping path is always
  # exercised and the spec is no longer data-dependent.
  let(:workspace) { create(:workspace, personal: false, join_policy: "open_link", name: "O'Brien Logistics") }
  let(:owner)     { create(:user) }
  let(:newcomer)  { create(:user) }
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
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    workspace.memberships.create!(user: owner, role: owner_role)
    sign_in(newcomer)
  end

  describe "POST /workspaces/:slug/joins/:token" do
    it "admits the user as a Member and redirects to the workspace" do
      expect {
        post workspace_join_path(workspace, token: link.token)
      }.to change(workspace.memberships, :count).by(1)

      membership = workspace.memberships.find_by!(user: newcomer)
      expect(membership.role).to eq(member_role)
      expect(response).to redirect_to(workspace_path(workspace))
    end

    it "rejects a revoked link" do
      link.revoke!
      expect {
        post workspace_join_path(workspace, token: link.token)
      }.not_to change(workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
    end

    it "rejects when the workspace's join_policy is not open_link" do
      workspace.update!(join_policy: "invite")
      expect {
        post workspace_join_path(workspace, token: link.token)
      }.not_to change(workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
    end

    it "rejects when the instance allowlist excludes :open_link" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      expect {
        post workspace_join_path(workspace, token: link.token)
      }.not_to change(workspace.memberships, :count)
      expect(response).to redirect_to(root_path)
    end

    it "surfaces a clean message when the workspace is at capacity" do
      workspace.update!(max_members: 1)  # owner already fills capacity
      post workspace_join_path(workspace, token: link.token)
      expect(workspace.memberships.find_by(user: newcomer)).to be_nil
      # A generic i18n message, never the raw model validation string.
      expect(flash[:alert]).to eq(I18n.t("workspaces.joins.create.could_not_join", workspace: workspace.name))
      expect(flash[:alert]).not_to match(/capacity|max_members/i)
    end

    it "redirects gracefully when the user is already a member" do
      workspace.memberships.create!(user: newcomer, role: member_role)
      post workspace_join_path(workspace, token: link.token)
      expect(response).to redirect_to(workspace_path(workspace))
    end

    it "returns the same neutral error for invalid + unauthorized cases (no info leak)" do
      # Confirms that "link doesn't exist" and "policy isn't open_link" surface
      # the same alert — don't reveal whether a specific workspace allows joins.
      workspace.update!(join_policy: "invite")
      post workspace_join_path(workspace, token: link.token)
      no_policy_alert = flash[:alert]

      post workspace_join_path(workspace, token: "totally-fake-token")
      no_link_alert = flash[:alert]

      expect(no_policy_alert).to be_present
      expect(no_link_alert).to eq(no_policy_alert)
    end
  end

  describe "GET /workspaces/:slug/joins/:token" do
    it "renders a confirmation page for a valid active link" do
      get workspace_join_path(workspace, token: link.token)
      expect(response).to have_http_status(:ok)
      expect(Capybara.string(response.body)).to have_text(workspace.name)
    end

    it "redirects with an error for a revoked link" do
      link.revoke!
      get workspace_join_path(workspace, token: link.token)
      expect(response).to redirect_to(root_path)
    end
  end
end

# Reshape 2b: unauthenticated branch. Top-level describe so it doesn't
# inherit the Flow A spec's `sign_in(newcomer)` before-hook. Visiting a
# valid join link without an account stashes the token in the session and
# routes the visitor through the registration flow. After email
# verification, claim_pending_join_link! admits them to the workspace.
RSpec.describe "Workspaces::Joins (Flow B: unauthenticated user via link)", type: :request do
  let(:workspace) { create(:workspace, personal: false, join_policy: "open_link", name: "O'Brien Logistics") }
  let(:owner) { create(:user) }
  let!(:owner_role) {
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    }
  }
  let(:link) { create(:workspace_join_link, workspace: workspace, created_by: owner) }

  before do
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    workspace.memberships.create!(user: owner, role: owner_role)
  end

  it "POST stashes the join token in the session and redirects to sign-in" do
    post workspace_join_path(workspace, token: link.token)

    expect(session[:pending_join_token]).to eq(link.token)
    expect(response).to redirect_to(new_session_path)
  end

  it "POST with a revoked link uses the neutral error (no session stash, no info leak)" do
    link.revoke!
    post workspace_join_path(workspace, token: link.token)

    expect(session[:pending_join_token]).to be_nil
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
  end

  it "GET renders the confirmation page without requiring auth" do
    get workspace_join_path(workspace, token: link.token)
    expect(response).to have_http_status(:ok)
    expect(Capybara.string(response.body)).to have_text(workspace.name)
  end
end
