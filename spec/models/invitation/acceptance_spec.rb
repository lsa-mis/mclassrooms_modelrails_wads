require "rails_helper"

# Invitation::Acceptance's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe Invitation, type: :model do
  describe "#accept! raise behavior" do
    let(:user) { create(:user) }

    it "raises Invitation::NotAcceptable when invitation is already accepted" do
      invitation = create(:invitation, :accepted)
      expect {
        invitation.accept!(user)
      }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
    end

    it "raises Invitation::NotAcceptable when invitation is expired" do
      invitation = create(:invitation, :expired)
      expect {
        invitation.accept!(user)
      }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
    end

    it "raises Invitation::NotAcceptable when invitation is declined" do
      invitation = create(:invitation, :declined)
      expect {
        invitation.accept!(user)
      }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
    end

    it "does NOT raise NotAcceptable on a valid pending invitation" do
      invitation = create(:invitation)
      expect {
        invitation.accept!(user)
      }.not_to raise_error
    end

    # G (SEC-1 follow-up): the invitation flow — the most common grant path —
    # logged membership.created with empty metadata and only the accepting
    # invitee as actor. The granter and granted role now ride as metadata
    # (the actor stays the invitee: they performed the accept).
    it "audits the granted membership with role and granter" do
      invitation = create(:invitation)
      invitation.accept!(user)

      membership = invitation.invitable.memberships.find_by(user: user)
      entry = ActivityLog.where(action: "membership.created", trackable: membership).last
      expect(entry).to be_present
      expect(entry.metadata["role"]).to eq(invitation.role.slug)
      expect(entry.metadata["granted_by"]).to eq(invitation.invited_by_id)
    end

    it "raises Invitation::NotAcceptable when the target workspace is suspended (workspace invitation)" do
      workspace = create(:workspace)
      invitation = create(:invitation, invitable: workspace)
      workspace.suspend!
      # Force user creation outside the expect block — onboarding callbacks
      # create their own membership, which would confound the count.
      user

      expect {
        invitation.accept!(user)
      }.to raise_error(Invitation::NotAcceptable, /no longer acceptable/i)
        .and change(Membership, :count).by(0)
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
      expect { invitation.accept!(create(:user)) }.to raise_error(Invitation::NotAcceptable)
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
      expect { invitation.accept!(user) }.to raise_error(Workspace::AlreadyMember)
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

  # Regression: capacity is enforced through the invitation acceptance path.
  # Membership-level capacity is also tested in spec/models/membership_spec.rb,
  # but the accept! flow goes through Invitation#accept_workspace_invitation!
  # which acquires workspace.lock! BEFORE checking the count (line 111 vs 118).
  # This test locks in that the lock-then-check sequence prevents over-capacity
  # acceptances, even on engines (e.g., PostgreSQL) where row-level locks are
  # the only serialization mechanism. SQLite's BEGIN IMMEDIATE provides
  # additional database-wide write serialization, but this test asserts the
  # business rule independent of engine.
  describe "#accept! capacity enforcement (regression)" do
    it "rejects acceptance when workspace is at max_members" do
      workspace = create(:workspace, max_members: 2)
      create(:membership, :owner, workspace: workspace)
      create(:membership, workspace: workspace)
      invitation = create(:invitation, invitable: workspace)
      user = create(:user)

      expect { invitation.accept!(user) }
        .to raise_error(Workspace::AtCapacity)

      expect(workspace.memberships.kept.count).to eq(2)
      expect(invitation.reload).to be_pending
    end
  end

  # Shared consumption core used by both the session-based (Signupable) and
  # column-based (Authentication#claim_pending_invitation!) acceptance paths.
  describe ".consume!" do
    let(:user) { create(:user) }
    let(:workspace) { create(:workspace) }

    it "accepts the matching invitation and returns it" do
      invitation = create(:invitation, invitable: workspace)

      result = Invitation.consume!(token: invitation.token, user: user)

      expect(result).to eq(invitation)
      expect(invitation.reload).to be_accepted
      expect(workspace.memberships.kept.exists?(user: user)).to be true
    end

    it "returns nil when the token is blank" do
      expect(Invitation.consume!(token: nil, user: user)).to be_nil
      expect(Invitation.consume!(token: "", user: user)).to be_nil
    end

    it "returns nil when no invitation matches the token" do
      expect(Invitation.consume!(token: "does-not-exist", user: user)).to be_nil
    end

    it "raises Invitation::NotAcceptable when the invitation is no longer acceptable" do
      invitation = create(:invitation, :accepted, invitable: workspace)

      expect {
        Invitation.consume!(token: invitation.token, user: user)
      }.to raise_error(Invitation::NotAcceptable)
    end

    context "with expected_email (email-match guard)" do
      it "accepts when the proven email matches the invitation email (case-insensitive)" do
        invitation = create(:invitation, invitable: workspace, email: "Invitee@Example.com")
        matching = create(:user, email_address: "invitee@example.com")

        result = Invitation.consume!(token: invitation.token, user: matching, expected_email: matching.email_address)

        expect(result).to eq(invitation)
        expect(invitation.reload).to be_accepted
      end

      it "raises EmailMismatch when the proven email differs from the invitation email" do
        invitation = create(:invitation, invitable: workspace, email: "invitee@example.com")
        other = create(:user, email_address: "someone-else@example.com")

        expect {
          Invitation.consume!(token: invitation.token, user: other, expected_email: other.email_address)
        }.to raise_error(Invitation::EmailMismatch)

        expect(invitation.reload).to be_pending
        expect(workspace.memberships.kept.exists?(user: other)).to be false
      end

      it "is a kind of NotAcceptable so existing boundary rescues still catch it" do
        expect(Invitation::EmailMismatch.ancestors).to include(Invitation::NotAcceptable)
      end

      it "consumes a magic-link invitation (nil email) regardless of expected_email" do
        invitation = create(:invitation, :magic_link, invitable: workspace)
        anyone = create(:user, email_address: "anyone@example.com")

        result = Invitation.consume!(token: invitation.token, user: anyone, expected_email: anyone.email_address)

        expect(result).to eq(invitation)
        expect(invitation.reload).to be_accepted
      end

      it "skips the guard when expected_email is not provided (direct callers)" do
        invitation = create(:invitation, invitable: workspace, email: "invitee@example.com")
        # user's email differs, but no expected_email is passed → no guard
        result = Invitation.consume!(token: invitation.token, user: user)

        expect(result).to eq(invitation)
      end
    end
  end

  # Reshape 1 reconciliation: under :shared posture, User#onboard_workspace
  # pre-creates a Member membership at signup. The invitation flow must then
  # adopt the invitation's role rather than treating the existing membership
  # as a duplicate-accept error. Solo-default (:personal) semantics unchanged.
  describe "#accept! reconciles role under :shared posture" do
    let!(:shared_workspace) { create(:workspace, slug: "acme", personal: false) }
    let!(:admin_role) {
      Role.find_or_create_by!(slug: "admin", workspace_id: nil) do |r|
        r.name = "Admin"
        r.permissions = { manage_members: true, manage_projects: true, manage_settings: true }
      end
    }
    let!(:member_role) {
      Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
        r.name = "Member"
        r.permissions = { manage_projects: true }
      end
    }
    let(:inviter) { create(:user) }

    before do
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
      allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(shared_workspace.slug)
    end

    it "promotes the placeholder Member to the invitation's Admin role" do
      invitee = create(:user, email_address: "newbie@example.com")
      # Callback created a Member membership; verify state before reconciliation.
      placeholder = shared_workspace.memberships.find_by!(user: invitee)
      expect(placeholder.role).to eq(member_role)

      invitation = create(:invitation,
                          invitable: shared_workspace,
                          role: admin_role,
                          email: "newbie@example.com",
                          invited_by: inviter)

      expect {
        invitation.accept!(invitee)
      }.not_to raise_error

      expect(shared_workspace.memberships.where(user: invitee).count).to eq(1)
      expect(placeholder.reload.role).to eq(admin_role)
    end

    it "no-ops when the invitation's role matches the placeholder Member role" do
      invitee = create(:user, email_address: "samerole@example.com")
      invitation = create(:invitation,
                          invitable: shared_workspace,
                          role: member_role,
                          email: "samerole@example.com",
                          invited_by: inviter)

      expect { invitation.accept!(invitee) }.not_to raise_error
      expect(shared_workspace.memberships.where(user: invitee).count).to eq(1)
    end
  end
end
