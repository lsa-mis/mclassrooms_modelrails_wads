require "rails_helper"

RSpec.describe Invitation, type: :model do
  describe "validations" do
    it "requires an invitable" do
      invitation = build(:invitation, invitable: nil)
      expect(invitation).not_to be_valid
    end

    it "requires a role" do
      invitation = build(:invitation, role: nil)
      expect(invitation).not_to be_valid
    end

    it "requires an invited_by user" do
      invitation = build(:invitation, invited_by: nil)
      expect(invitation).not_to be_valid
    end

    it "requires expires_at" do
      invitation = build(:invitation, expires_at: nil)
      expect(invitation).not_to be_valid
    end
  end

  describe "token generation" do
    it "generates a token before create" do
      invitation = create(:invitation)
      expect(invitation.token).to be_present
    end

    it "generates unique tokens" do
      inv1 = create(:invitation)
      inv2 = create(:invitation)
      expect(inv1.token).not_to eq(inv2.token)
    end
  end

  describe "scopes" do
    it "returns pending invitations" do
      pending_inv = create(:invitation)
      create(:invitation, :accepted)
      expect(Invitation.pending).to contain_exactly(pending_inv)
    end

    it "excludes expired from pending" do
      create(:invitation, :expired)
      expect(Invitation.pending).to be_empty
    end
  end

  describe "#accept!" do
    let(:workspace) { create(:workspace) }
    let!(:invitation) { create(:invitation, invitable: workspace) }
    let!(:user) { create(:user) }

    it "creates a membership" do
      expect { invitation.accept!(user) }.to change(Membership, :count).by(1)
    end

    it "prevents double-accept" do
      invitation = create(:invitation, invitable: create(:workspace))
      user = create(:user)
      invitation.accept!(user)
      expect { invitation.accept!(create(:user)) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "sets accepted status" do
      invitation.accept!(user)
      expect(invitation.reload.status).to eq("accepted")
      expect(invitation.accepted_by).to eq(user)
      expect(invitation.accepted_at).to be_present
    end

    it "assigns the invitation's role to the membership" do
      invitation.accept!(user)
      membership = workspace.memberships.find_by(user: user)
      expect(membership.role).to eq(invitation.role)
    end

    it "raises if user is already a member" do
      create(:membership, user: user, workspace: workspace)
      expect { invitation.accept!(user) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#accept! reactivates discarded workspace membership" do
    it "reactivates discarded membership on workspace re-invite" do
      workspace = create(:workspace)
      invitation = create(:invitation, invitable: workspace)
      user = create(:user)
      old_membership = create(:membership, user: user, workspace: workspace)
      other_owner = create(:user)
      create(:membership, :owner, user: other_owner, workspace: workspace)
      old_membership.deactivate!

      invitation.accept!(user)
      expect(old_membership.reload).not_to be_discarded
    end
  end

  describe "#decline!" do
    let(:invitation) { create(:invitation) }

    it "sets declined status" do
      invitation.decline!
      expect(invitation.reload.status).to eq("declined")
      expect(invitation.declined_at).to be_present
    end
  end

  describe "#revoke!" do
    let(:invitation) { create(:invitation) }

    it "sets revoked status" do
      invitation.revoke!
      expect(invitation.reload.status).to eq("revoked")
      expect(invitation.revoked_at).to be_present
    end
  end

  describe "#resend!" do
    let(:invitation) { create(:invitation) }

    it "regenerates the token" do
      old_token = invitation.token
      invitation.resend!
      expect(invitation.reload.token).not_to eq(old_token)
    end

    it "resets the expiry" do
      invitation.update!(expires_at: 1.day.from_now)
      invitation.resend!
      expect(invitation.reload.expires_at).to be > 6.days.from_now
    end
  end

  describe "#expired?" do
    it "returns true when past expires_at" do
      invitation = build(:invitation, expires_at: 1.hour.ago)
      expect(invitation).to be_expired
    end

    it "returns false when before expires_at" do
      invitation = build(:invitation, expires_at: 1.hour.from_now)
      expect(invitation).not_to be_expired
    end
  end

  describe "#magic_link?" do
    it "returns true when email is nil" do
      invitation = build(:invitation, :magic_link)
      expect(invitation).to be_magic_link
    end

    it "returns false when email is present" do
      invitation = build(:invitation)
      expect(invitation).not_to be_magic_link
    end
  end

  describe "#accept! for project invitation" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }
    let!(:owner_membership) { create(:membership, :owner, user: owner, workspace: workspace) }
    let(:project) { create(:project, workspace: workspace, created_by: owner) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
    let(:invitation) do
      project.invitations.create!(
        email: "project-invitee@example.com",
        role: viewer_role,
        project_role: "editor",
        invited_by: owner,
        expires_at: 7.days.from_now
      )
    end

    it "creates workspace membership and project membership" do
      invitee = create(:user, email_address: "project-invitee@example.com")
      invitation.accept!(invitee)
      expect(workspace.memberships.kept.exists?(user: invitee)).to be true
      expect(project.project_memberships.exists?(user: invitee)).to be true
    end

    it "assigns the correct project role" do
      invitee = create(:user, email_address: "project-invitee2@example.com")
      invitation2 = project.invitations.create!(
        email: "project-invitee2@example.com",
        role: viewer_role,
        project_role: "viewer",
        invited_by: owner,
        expires_at: 7.days.from_now
      )
      invitation2.accept!(invitee)
      pm = project.project_memberships.find_by(user: invitee)
      expect(pm).to be_viewer
    end

    it "raises for discarded project" do
      project.discard!
      invitee = create(:user)
      expect { invitation.accept!(invitee) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "project_role validation" do
    it "accepts editor" do
      inv = build(:invitation, project_role: "editor")
      inv.valid?
      expect(inv.errors[:project_role]).to be_empty
    end

    it "accepts viewer" do
      inv = build(:invitation, project_role: "viewer")
      inv.valid?
      expect(inv.errors[:project_role]).to be_empty
    end

    it "rejects creator" do
      inv = build(:invitation, project_role: "creator")
      expect(inv).not_to be_valid
      expect(inv.errors[:project_role]).to be_present
    end

    it "accepts nil (for workspace invitations)" do
      inv = build(:invitation, project_role: nil)
      inv.valid?
      expect(inv.errors[:project_role]).to be_empty
    end
  end

  describe "email format validation" do
    it "rejects malformed email" do
      inv = build(:invitation, email: "not-an-email")
      expect(inv).not_to be_valid
      expect(inv.errors[:email]).to be_present
    end

    it "accepts valid email" do
      inv = build(:invitation, email: "valid@example.com")
      inv.valid?
      expect(inv.errors[:email]).to be_empty
    end

    it "accepts nil email (magic links)" do
      inv = build(:invitation, email: nil)
      inv.valid?
      expect(inv.errors[:email]).to be_empty
    end
  end
end
