require "rails_helper"

RSpec.describe WorkspaceScoped, type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before do
    sign_in(user)
  end

  describe "touch_membership_last_accessed" do
    it "updates the membership's last_accessed_at when visiting a workspace-scoped page" do
      freeze_time do
        get workspace_path(workspace)
        expect(membership.reload.last_accessed_at).to eq(Time.current)
      end
    end

    it "does not touch discarded memberships" do
      original = 1.day.ago
      membership.update_column(:last_accessed_at, original)
      membership.update!(discarded_at: Time.current)

      # Discarded membership shouldn't be touched; visiting the workspace will
      # raise/redirect via set_workspace's RecordNotFound branch.
      get workspace_path(workspace)
      expect(membership.reload.last_accessed_at).to be_within(1.second).of(original)
    end

    it "silently swallows touch failures (Rails.error.report)" do
      allow(Membership).to receive(:where).and_call_original
      # Inject a failure on the touch query only. The double answers `where` with
      # itself because the touch chains a staleness predicate onto this relation
      # (#171) — the property under test is that the failure is swallowed, not
      # how many links the chain has.
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
