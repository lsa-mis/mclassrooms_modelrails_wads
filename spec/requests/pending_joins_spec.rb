require "rails_helper"

# The pre-existing user's own parked open-link join (Flow B). The token is
# stashed by an unauthenticated join POST and survives login (SEC-4's
# SESSION_KEYS_SURVIVING_LOGIN), so a password sign-in leaves it in the session
# for these actions to accept or dismiss.
RSpec.describe "PendingJoins", type: :request do
  let(:user) { create(:user, password: "SecureP@ssw0rd123!") }
  let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
  let(:link) { create(:workspace_join_link, workspace: workspace) }

  before do
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }

    post workspace_join_path(workspace, token: link.plaintext_token) # stash (unauthenticated)
    sign_in(user)                                                    # preserves the token
  end

  describe "POST /pending_join (accept)" do
    it "admits the user and announces it" do
      post pending_join_path

      expect(response).to redirect_to(workspace_path(workspace))
      expect(flash[:notice]).to eq(I18n.t("pending_joins.create.joined", workspace: workspace.name))
      expect(user.memberships.kept.where(workspace: workspace)).to exist
      expect(session[:pending_join_token]).to be_nil
    end

    it "reports the join as unavailable when the link was revoked in the meantime" do
      link.revoke!

      post pending_join_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("pending_joins.create.unavailable"))
      expect(user.memberships.kept.where(workspace: workspace)).not_to exist
    end

    it "reports a generic failure when the workspace is at capacity" do
      workspace.update!(max_members: 1)
      create(:membership, workspace: workspace, user: create(:user))

      post pending_join_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("pending_joins.create.could_not_join", workspace: workspace.name))
      expect(user.memberships.kept.where(workspace: workspace)).not_to exist
    end
  end

  describe "DELETE /pending_join (dismiss)" do
    it "clears the parked join and announces the dismissal" do
      delete pending_join_path

      expect(flash[:notice]).to eq(I18n.t("pending_joins.destroy.dismissed"))
      expect(session[:pending_join_token]).to be_nil
      expect(user.memberships.kept.where(workspace: workspace)).not_to exist
    end
  end
end
