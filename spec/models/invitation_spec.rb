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
    let(:invitation) { create(:invitation, invitable: workspace) }
    let(:user) { create(:user) }

    it "creates a membership" do
      expect { invitation.accept!(user) }.to change(Membership, :count).by(1)
    end

    it "sets accepted status" do
      invitation.accept!(user)
      expect(invitation.reload.status).to eq("accepted")
      expect(invitation.accepted_by).to eq(user)
      expect(invitation.accepted_at).to be_present
    end

    it "assigns the invitation's role to the membership" do
      invitation.accept!(user)
      membership = Membership.last
      expect(membership.role).to eq(invitation.role)
    end

    it "raises if user is already a member" do
      create(:membership, user: user, workspace: workspace)
      expect { invitation.accept!(user) }.to raise_error(ActiveRecord::RecordInvalid)
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
end
