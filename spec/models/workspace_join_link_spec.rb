require "rails_helper"

RSpec.describe WorkspaceJoinLink, type: :model do
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }

  describe "creation" do
    it "generates a URL-safe plaintext token exposed once, storing only its digest" do
      link = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)

      expect(link.plaintext_token).to be_present
      expect(link.plaintext_token.length).to be >= 20
      expect(link.token_digest).to eq(WorkspaceJoinLink.digest(link.plaintext_token))
    end

    it "does not persist the plaintext token (only the digest is stored)" do
      link = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)

      # A fresh load from the DB has the digest but no way back to the plaintext.
      reloaded = WorkspaceJoinLink.find(link.id)
      expect(reloaded.plaintext_token).to be_nil
      expect(reloaded.token_digest).to be_present
    end

    it "requires a workspace and a created_by user" do
      expect(WorkspaceJoinLink.new(created_by: user)).not_to be_valid
      expect(WorkspaceJoinLink.new(workspace: workspace)).not_to be_valid
    end
  end

  describe ".digest" do
    it "is a stable SHA256 hex digest of the plaintext" do
      expect(WorkspaceJoinLink.digest("abc")).to eq(Digest::SHA256.hexdigest("abc"))
      expect(WorkspaceJoinLink.digest("abc")).to eq(WorkspaceJoinLink.digest("abc"))
    end
  end

  describe ".find_active" do
    it "finds an active link by its plaintext token" do
      link = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      expect(WorkspaceJoinLink.find_active(link.plaintext_token)).to eq(link)
    end

    it "does not find a revoked link" do
      link = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      plaintext = link.plaintext_token
      link.revoke!
      expect(WorkspaceJoinLink.find_active(plaintext)).to be_nil
    end

    it "returns nil for an unknown token" do
      expect(WorkspaceJoinLink.find_active("nope")).to be_nil
    end
  end

  describe ".find_active_by_digest" do
    it "finds an active link by a parked digest, and skips revoked ones" do
      link = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      digest = link.token_digest
      expect(WorkspaceJoinLink.find_active_by_digest(digest)).to eq(link)
      link.revoke!
      expect(WorkspaceJoinLink.find_active_by_digest(digest)).to be_nil
    end
  end

  describe "#admit" do
    let(:open_workspace) { create(:workspace, personal: false, join_policy: "open_link") }
    let(:link) { WorkspaceJoinLink.create!(workspace: open_workspace, created_by: user) }
    let(:joiner) { create(:user) }

    before do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
    end

    it "admits the user at the self-join role when the workspace accepts open joins" do
      link.admit(joiner)
      membership = open_workspace.memberships.find_by(user: joiner)
      expect(membership.role.slug).to eq("member")
    end

    it "is a no-op for a stale link (workspace no longer accepting open joins)" do
      joiner # create outside the expect — onboarding creates its own membership
      open_workspace.update!(join_policy: "invite")
      expect { link.admit(joiner) }.not_to change { open_workspace.memberships.count }
    end

    it "raises Workspace::AlreadyMember for a duplicate join (callers decide how to treat it)" do
      create(:membership, workspace: open_workspace, user: joiner)
      expect { link.admit(joiner) }.to raise_error(Workspace::AlreadyMember)
    end
  end

  describe "digest uniqueness" do
    it "rejects a duplicate digest" do
      WorkspaceJoinLink.create!(workspace: workspace, created_by: user, token_digest: "fixed-digest-xyz")
      dup = WorkspaceJoinLink.new(workspace: create(:workspace), created_by: user, token_digest: "fixed-digest-xyz")
      expect(dup).not_to be_valid
      expect(dup.errors[:token_digest]).to be_present
    end
  end

  describe "one active link per workspace (DB partial unique index)" do
    it "rejects a second active link for the same workspace" do
      WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      expect {
        WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new active link once the previous one is revoked" do
      first = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      first.revoke!

      expect {
        WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      }.not_to raise_error
    end

    it "allows simultaneous active links in different workspaces" do
      other_workspace = create(:workspace)
      WorkspaceJoinLink.create!(workspace: workspace, created_by: user)

      expect {
        WorkspaceJoinLink.create!(workspace: other_workspace, created_by: user)
      }.not_to raise_error
    end
  end

  describe ".active scope" do
    it "includes links with no revoked_at and excludes revoked ones" do
      active = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)
      revoked = WorkspaceJoinLink.create!(workspace: create(:workspace), created_by: user, revoked_at: 1.minute.ago)

      expect(WorkspaceJoinLink.active).to include(active)
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

  describe "#masked_token" do
    it "is a non-secret stub derived from the digest, not the plaintext" do
      link = WorkspaceJoinLink.create!(workspace: workspace, created_by: user)

      expect(link.masked_token).to include(link.token_digest.last(6))
      expect(link.masked_token).not_to include(link.plaintext_token)
    end
  end
end
