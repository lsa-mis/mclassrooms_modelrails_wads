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

  describe "Invitation::NotAcceptable" do
    it "is a standalone StandardError (not an ActiveRecord::RecordInvalid)" do
      expect(Invitation::NotAcceptable.ancestors).to include(StandardError)
      expect(Invitation::NotAcceptable.ancestors).not_to include(ActiveRecord::RecordInvalid)
    end
  end

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
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(workspace.memberships.kept.count).to eq(2)
      expect(invitation.reload).to be_pending
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

  describe "#decline! guard" do
    it "prevents declining an already accepted invitation" do
      invitation = create(:invitation, invitable: create(:workspace))
      user = create(:user)
      invitation.accept!(user)
      expect { invitation.decline! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#revoke! guard" do
    it "prevents revoking an already declined invitation" do
      invitation = create(:invitation)
      invitation.decline!
      expect { invitation.revoke! }.to raise_error(ActiveRecord::RecordInvalid)
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

  describe ".bulk_invite!" do
    let(:workspace) { create(:workspace) }
    let(:role) { workspace.effective_roles.first }
    let(:inviter) { create(:user) }

    before do
      create(:membership, :owner, user: inviter, workspace: workspace)
    end

    it "creates invitations for valid emails and returns counts" do
      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "alice@example.com", "bob@example.com" ],
        role: role,
        invited_by: inviter
      )

      expect(result[:sent]).to eq(2)
      expect(result[:skipped]).to eq(0)
      expect(workspace.invitations.count).to eq(2)
    end

    it "skips invalid email formats" do
      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "not-an-email", "valid@example.com" ],
        role: role,
        invited_by: inviter
      )

      expect(result[:sent]).to eq(1)
      expect(result[:skipped]).to eq(1)
    end

    it "skips emails that are already workspace members" do
      existing_user = create(:user, email_address: "member@example.com")
      create(:membership, user: existing_user, workspace: workspace)

      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "member@example.com", "new@example.com" ],
        role: role,
        invited_by: inviter
      )

      expect(result[:sent]).to eq(1)
      expect(result[:skipped]).to eq(1)
    end

    it "skips emails with pending invitations" do
      workspace.invitations.create!(
        email: "pending@example.com",
        role: role,
        invited_by: inviter,
        expires_at: 7.days.from_now
      )

      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "pending@example.com", "new@example.com" ],
        role: role,
        invited_by: inviter
      )

      expect(result[:sent]).to eq(1)
      expect(result[:skipped]).to eq(1)
    end

    it "queues invitation mailers" do
      expect {
        Invitation.bulk_invite!(
          workspace: workspace,
          emails: [ "alice@example.com" ],
          role: role,
          invited_by: inviter
        )
      }.to have_enqueued_mail(InvitationMailer, :invite)
    end

    it "skips an email whose pending invitation was created concurrently instead of aborting the batch" do
      # The lost race: another request commits the same pending invitation
      # after bulk_invite! preloads pending emails but before create!. Hide
      # the existing row from the preload so the partial unique index
      # (index_invitations_on_email_and_invitable_pending) raises for real.
      workspace.invitations.create!(
        email: "raced@example.com",
        role: role,
        invited_by: inviter,
        expires_at: 7.days.from_now
      )
      invitations = workspace.invitations
      allow(workspace).to receive(:invitations).and_return(invitations)
      allow(invitations).to receive(:pending).and_return(Invitation.none)

      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "raced@example.com", "fresh@example.com" ],
        role: role,
        invited_by: inviter
      )

      expect(result[:sent]).to eq(1)
      expect(result[:skipped]).to eq(1)
      expect(Invitation.where(email: "raced@example.com").count).to eq(1)
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
  describe "#resolved_workspace" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }

    it "returns the invitable when invitable is a Workspace" do
      invitation = create(:invitation, invitable: workspace)
      expect(invitation.resolved_workspace).to eq(workspace)
    end
  end
  describe "#acceptable?" do
    it "returns true for a pending, non-expired invitation" do
      invitation = build(:invitation)
      expect(invitation.acceptable?).to be true
    end

    it "returns false for an expired invitation" do
      invitation = build(:invitation, :expired)
      expect(invitation.acceptable?).to be false
    end

    it "returns false for an accepted invitation" do
      invitation = build(:invitation, :accepted)
      expect(invitation.acceptable?).to be false
    end

    it "returns false for a declined invitation" do
      invitation = build(:invitation, :declined)
      expect(invitation.acceptable?).to be false
    end

    it "returns false for a revoked invitation" do
      invitation = build(:invitation, :revoked)
      expect(invitation.acceptable?).to be false
    end
  end

  describe "#expires_in_hours" do
    # Use ceil so "expires in 1 hour" reads naturally at T-30min instead of "0
    # hours" — the user-facing copy is hours-remaining, not floor of hours.
    it "ceils a fractional remaining window to the next whole hour" do
      freeze_time do
        invitation = build(:invitation, expires_at: 90.minutes.from_now)
        expect(invitation.expires_in_hours).to eq(2)
      end
    end

    it "ceils a sub-hour remaining window to 1" do
      freeze_time do
        invitation = build(:invitation, expires_at: 30.minutes.from_now)
        expect(invitation.expires_in_hours).to eq(1)
      end
    end

    it "returns the exact number when the window is exactly an integer hour" do
      freeze_time do
        invitation = build(:invitation, expires_at: 24.hours.from_now)
        expect(invitation.expires_in_hours).to eq(24)
      end
    end

    it "returns 0 when the invitation is exactly at expiry" do
      freeze_time do
        invitation = build(:invitation, expires_at: Time.current)
        expect(invitation.expires_in_hours).to eq(0)
      end
    end

    it "returns 0 when the invitation has already expired" do
      freeze_time do
        invitation = build(:invitation, expires_at: 5.minutes.ago)
        expect(invitation.expires_in_hours).to eq(0)
      end
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
        r.permissions = { manage_members: true, manage_settings: true }
      end
    }
    let!(:member_role) {
      Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
        r.name = "Member"
        r.permissions = {}
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

  describe "member-invite role requirement (regression for client-variant change)" do
    it "still requires a role for a normal (non-client) workspace invite" do
      inv = build(:invitation, role: nil)
      expect(inv).not_to be_valid
      expect(inv.errors[:role]).to be_present
    end

    it "accepts a member invite with a role and creates a membership" do
      workspace = create(:workspace)
      role = Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
      inv = create(:invitation, invitable: workspace, role: role)
      user = create(:user, :with_zero_workspaces)
      expect { inv.accept!(user) }.to change { workspace.memberships.kept.count }.by(1)
    end
  end

  # Wiring coverage: drive accept!/decline! and assert the notifier fires.
  # The notifiers themselves are specced in spec/notifiers/; without these,
  # the after_update_commit registrations could be deleted and the suite
  # would stay green.
  describe "notification wiring" do
    let(:workspace) { create(:workspace) }
    let(:inviter) { create(:user) }
    let(:invitation) { create(:invitation, invitable: workspace, invited_by: inviter, email: "invitee@example.com") }

    describe "accepted (after_update_commit)" do
      it "notifies the inviter when someone else accepts" do
        acceptor = create(:user)
        expect {
          invitation.accept!(acceptor)
        }.to change { Noticed::Event.where(type: "WorkspaceInvitationAcceptedNotifier").count }.by(1)
        event = Noticed::Event.where(type: "WorkspaceInvitationAcceptedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ inviter ])
      end

      it "does not notify when the inviter accepts their own invitation" do
        expect {
          invitation.accept!(inviter)
        }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationAcceptedNotifier").count }
      end
    end

    describe "declined (after_update_commit)" do
      it "notifies the inviter" do
        expect {
          invitation.decline!
        }.to change { Noticed::Event.where(type: "WorkspaceInvitationDeclinedNotifier").count }.by(1)
        event = Noticed::Event.where(type: "WorkspaceInvitationDeclinedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ inviter ])
      end

      it "does not notify when the declined invitation was addressed to the inviter" do
        self_invitation = create(:invitation, invitable: workspace, invited_by: inviter, email: inviter.email_address)
        expect {
          self_invitation.decline!
        }.not_to change { Noticed::Event.where(type: "WorkspaceInvitationDeclinedNotifier").count }
      end
    end
  end
end
