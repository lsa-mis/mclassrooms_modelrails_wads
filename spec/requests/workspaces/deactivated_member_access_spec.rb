# frozen_string_literal: true

require "rails_helper"

# #931: a removed member who still held a workspace URL got an endless
# redirect. `User#workspaces` ran through EVERY membership, discarded ones
# included, so WorkspaceScoped resolved the workspace anyway, the policy then
# refused, and `user_not_authorized` sent the browser back to the very page
# that had just refused it.
RSpec.describe "Deactivated member workspace access", type: :request do
  let(:workspace) { create(:workspace) }
  let(:owner) { create(:user) }
  let(:member) { create(:user) }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    create(:membership, user: member, workspace: workspace).deactivate!
    sign_in(member)
  end

  it "sends a removed member to the workspace index, not back to the workspace" do
    get workspace_path(workspace)

    expect(response).to redirect_to(workspaces_path)
    expect(response.headers["Location"]).not_to include(workspace_path(workspace))
    expect(flash[:alert]).to eq(I18n.t("workspaces.not_found"))
  end

  it "settles on the index in a single hop" do
    get workspace_path(workspace)
    follow_redirect!

    expect(response).to have_http_status(:ok)
  end

  # Defense in depth for the same loop: whatever refuses a request at the
  # workspace's OWN path, the handler must not answer with that path.
  # Fork: `not_authorized_redirect_path` sends any refused-but-viewing member
  # to find_a_room_path (the actual product surface for this single-shared-
  # workspace deployment), not the template's generic workspaces_path — see
  # ApplicationController#not_authorized_redirect_path. Either destination
  # breaks the loop; this pins the fork's actual one.
  describe "the not-authorized handler" do
    let(:visitor) { create(:user) }

    before do
      create(:membership, user: visitor, workspace: workspace)
      sign_in(visitor)
      # Nothing real refuses a kept member on this page any more (that was the
      # bug), so the refusal is stubbed to reach the handler branch.
      allow(WorkspacePolicy).to receive(:new)
        .and_return(instance_double(WorkspacePolicy, show?: false))
    end

    it "redirects to find_a_room rather than to the refused page" do
      get workspace_path(workspace)

      expect(response).to redirect_to(find_a_room_path)
      expect(response.headers["Location"]).not_to include(workspace_path(workspace))
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
    end
  end
end
