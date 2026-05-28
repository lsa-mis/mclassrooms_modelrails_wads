require "rails_helper"

RSpec.describe WorkspaceJoinLink, type: :model do
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }

  describe "creation" do
    it "auto-populates a URL-safe token via has_secure_token" do
      link = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      expect(link.token).to be_present
      expect(link.token.length).to be >= 20
    end

    it "rejects duplicate tokens (DB unique index)" do
      WorkspaceJoinLink.create!(workspace: workspace, created_by: user, token: "fixed-token-xyz")
      expect {
        WorkspaceJoinLink.create!(workspace: workspace, created_by: user, token: "fixed-token-xyz")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "requires a workspace and a created_by user" do
      expect(WorkspaceJoinLink.new(created_by: user)).not_to be_valid
      expect(WorkspaceJoinLink.new(workspace: workspace)).not_to be_valid
    end
  end

  describe ".active scope" do
    it "includes links with no revoked_at" do
      active = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      expect(WorkspaceJoinLink.active).to include(active)
    end

    it "excludes revoked links" do
      revoked = WorkspaceJoinLink.create!(workspace: workspace, created_by: user, revoked_at: 1.minute.ago)
      expect(WorkspaceJoinLink.active).not_to include(revoked)
    end
  end

  describe "#revoke! and #revoked?" do
    it "stamps revoked_at and reports revoked?" do
      link = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      expect(link).not_to be_revoked

      freeze_time do
        link.revoke!
        expect(link.revoked_at).to eq(Time.current)
        expect(link).to be_revoked
      end
    end
  end

  describe "regenerate_token (the atomic-rotate primitive from has_secure_token)" do
    it "produces a new token value" do
      link = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      original = link.token

      link.regenerate_token

      expect(link.reload.token).not_to eq(original)
    end
  end
end
