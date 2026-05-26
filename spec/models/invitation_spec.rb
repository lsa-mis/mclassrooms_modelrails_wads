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

    it "rejects project-invitation acceptance when workspace is at capacity" do
      workspace = create(:workspace, max_members: 2)
      owner_membership = create(:membership, :owner, workspace: workspace)
      create(:membership, workspace: workspace)
      # Reuse the owner as the project's created_by to avoid the project factory's
      # after_create membership backfill (which would push the workspace over cap
      # before our invitation acceptance even runs — see spec/factories/projects.rb).
      project = create(:project, workspace: workspace, created_by: owner_membership.user)
      invitation = create(:invitation, invitable: project, project_role: "editor")
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

  describe "#accept! when user is already a project member" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }
    let(:project) { create(:project, workspace: workspace, created_by: owner) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
    let(:invitation) do
      project.invitations.create!(
        email: "already-member@example.com",
        role: viewer_role,
        project_role: "editor",
        invited_by: owner,
        expires_at: 7.days.from_now
      )
    end

    before do
      create(:membership, :owner, user: owner, workspace: workspace)
    end

    it "raises when user is already a project member" do
      existing_user = create(:user, email_address: "already-member@example.com")
      create(:membership, user: existing_user, workspace: workspace)
      create(:project_membership, project: project, user: existing_user)

      expect { invitation.accept!(existing_user) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#accept! reactivates discarded workspace membership for project invitation" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }
    let(:project) { create(:project, workspace: workspace, created_by: owner) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }

    before { create(:membership, :owner, user: owner, workspace: workspace) }

    it "reactivates the discarded membership" do
      user = create(:user)
      ws_membership = create(:membership, user: user, workspace: workspace)
      other_owner = create(:membership, :owner, workspace: workspace)
      ws_membership.deactivate!

      invitation = project.invitations.create!(
        email: user.email_address,
        role: viewer_role,
        project_role: "editor",
        invited_by: owner,
        expires_at: 7.days.from_now
      )

      invitation.accept!(user)
      expect(ws_membership.reload).not_to be_discarded
      expect(project.project_memberships.exists?(user: user)).to be true
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

    it "returns the project's workspace when invitable is a Project" do
      create(:membership, :owner, user: owner, workspace: workspace)
      project = create(:project, workspace: workspace, created_by: owner)
      invitation = create(:invitation, invitable: project, project_role: "editor")
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
  end
end
