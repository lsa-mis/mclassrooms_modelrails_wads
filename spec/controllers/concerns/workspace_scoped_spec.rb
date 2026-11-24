require "rails_helper"

RSpec.describe WorkspaceScoped, type: :request do
  def sign_in_workspace_owner
    workspace = create(:workspace)
    owner = sign_in_as_owner_of(workspace)
    owner.memberships.find_by!(workspace: workspace)
  end

  describe "touch_membership_last_accessed" do
    it "updates the membership's last_accessed_at when visiting a workspace-scoped page" do
      membership = sign_in_workspace_owner
      workspace = membership.workspace

      freeze_time do
        get workspace_path(workspace)
        expect(membership.reload.last_accessed_at).to eq(Time.current)
      end
    end

    it "does not touch discarded memberships" do
      membership = sign_in_workspace_owner
      workspace = membership.workspace
      original = 1.day.ago
      membership.update_column(:last_accessed_at, original)
      membership.update!(discarded_at: Time.current)

      # Discarded membership shouldn't be touched; visiting the workspace will
      # raise/redirect via set_workspace's RecordNotFound branch.
      get workspace_path(workspace)
      expect(membership.reload.last_accessed_at).to be_within(1.second).of(original)
    end

    it "silently swallows touch failures (Rails.error.report)" do
      workspace = sign_in_workspace_owner.workspace
      allow(Membership).to receive(:where).and_call_original
      # `where` returns itself because the touch chains a staleness predicate (#171).
      bad_relation = double("ActiveRecord::Relation")
      allow(bad_relation).to receive(:where).and_return(bad_relation)
      allow(bad_relation).to receive(:update_all).and_raise(ActiveRecord::StatementInvalid, "boom")
      allow(Membership).to receive(:where)
        .with(hash_including(:user_id, :workspace_id, :discarded_at))
        .and_return(bad_relation)

      expect(Rails.error).to receive(:report).with(instance_of(ActiveRecord::StatementInvalid), anything)
      expect { get workspace_path(workspace) }.not_to raise_error
    end
  end
end
