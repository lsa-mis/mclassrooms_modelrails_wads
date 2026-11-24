require "rails_helper"

RSpec.describe PendingClaims do
  def ensure_member_role
    Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
      r.name = "Member"
      r.permissions = { manage_projects: true }
    end
  end

  describe "#claim! (signup-time, abort semantics)" do
    describe "invitation token" do
      it "is a no-op when no invitation token was parked" do
        user = create(:user)
        claims = described_class.new

        expect { claims.claim!(user) }.not_to change(user.workspaces, :count)
        expect(claims.spent).to be_empty
        expect(claims.problems).to be_empty
      end

      it "leaves an unmatched token unspent (signup keeps it parked)" do
        user = create(:user)
        claims = described_class.new(invitation_token: "no-such-token")

        claims.claim!(user)

        expect(claims.spent).not_to include(:invitation)
        expect(claims.problems).to be_empty
      end

      it "consumes a valid invitation and marks the token spent" do
        user = create(:user)
        invitation = create(:invitation, email: user.email_address)
        claims = described_class.new(invitation_token: invitation.token)

        claims.claim!(user)

        expect(invitation.reload).to be_accepted
        expect(user.workspaces).to include(invitation.invitable)
        expect(claims.spent).to include(:invitation)
        expect(claims.problems).to be_empty
      end

      it "skips a mismatched invitation without raising: spent + problem, invitation stays pending" do
        user = create(:user)
        invitation = create(:invitation, email: "invited@example.com")
        claims = described_class.new(invitation_token: invitation.token)

        expect { claims.claim!(user) }.not_to raise_error

        expect(invitation.reload).to be_pending
        expect(claims.spent).to include(:invitation)
        expect(claims.problems).to eq([ :invitation_email_mismatch ])
      end

      it "raises Invitation::NotAcceptable for a stale invitation and still marks the token spent" do
        user = create(:user)
        invitation = create(:invitation, :expired, email: user.email_address)
        claims = described_class.new(invitation_token: invitation.token)

        expect { claims.claim!(user) }.to raise_error(Invitation::NotAcceptable)

        expect(claims.spent).to include(:invitation)
      end
    end

    describe "join-link token" do
      before do
        permit_open_join_links
      end

      it "admits a newly registered user through an active link and spends the token" do
        user = create(:user)
        ensure_member_role
        workspace = create(:workspace, :open_link)
        link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
        claims = described_class.new(join_token: link.plaintext_token)

        claims.claim!(user, newly_registered: true)

        expect(user.workspaces).to include(workspace)
        expect(claims.spent).to include(:join)
        expect(claims.problems).to be_empty
      end

      it "leaves a still-valid token unspent for a pre-existing user (re-consent guard)" do
        user = create(:user)
        ensure_member_role
        workspace = create(:workspace, :open_link)
        link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
        claims = described_class.new(join_token: link.plaintext_token)

        claims.claim!(user, newly_registered: false)

        expect(user.workspaces).not_to include(workspace)
        expect(claims.spent).not_to include(:join)
      end

      it "spends a revoked link's token silently, even for a pre-existing user" do
        user = create(:user)
        ensure_member_role
        workspace = create(:workspace, :open_link)
        link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
        link.revoke!
        claims = described_class.new(join_token: link.plaintext_token)

        claims.claim!(user, newly_registered: false)

        expect(user.workspaces).not_to include(workspace)
        expect(claims.spent).to include(:join)
        expect(claims.problems).to be_empty
      end

      it "treats Workspace::AlreadyMember as benign: spent, no problem, no raise" do
        user = create(:user)
        member_role = ensure_member_role
        workspace = create(:workspace, :open_link)
        link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
        workspace.admit(user, role: member_role)
        claims = described_class.new(join_token: link.plaintext_token)

        expect { claims.claim!(user, newly_registered: true) }.not_to raise_error

        expect(claims.spent).to include(:join)
        expect(claims.problems).to be_empty
      end

      it "raises Workspace::AtCapacity and still spends the token" do
        user = create(:user)
        member_role = ensure_member_role
        workspace = create(:workspace, :open_link)
        link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
        workspace.update!(max_members: 1)
        create(:membership, workspace: workspace, user: create(:user), role: member_role)
        claims = described_class.new(join_token: link.plaintext_token)

        expect { claims.claim!(user, newly_registered: true) }.to raise_error(Workspace::AtCapacity)

        expect(claims.spent).to include(:join)
      end
    end
  end

  describe "#claim (verification-time, continue semantics)" do
    describe "invitation token" do
      it "spends an unmatched token (the claim is one-shot; verify never retries)" do
        user = create(:user)
        claims = described_class.new(invitation_token: "no-such-token")

        claims.claim(user)

        expect(claims.spent).to include(:invitation)
        expect(claims.problems).to be_empty
      end

      it "consumes a valid invitation and marks the token spent" do
        user = create(:user)
        invitation = create(:invitation, email: user.email_address)
        claims = described_class.new(invitation_token: invitation.token)

        claims.claim(user)

        expect(invitation.reload).to be_accepted
        expect(claims.spent).to include(:invitation)
      end

      it "records :invitation_email_mismatch for a mismatched invitation without raising" do
        user = create(:user)
        invitation = create(:invitation, email: "invited@example.com")
        claims = described_class.new(invitation_token: invitation.token)

        expect { claims.claim(user) }.not_to raise_error

        expect(invitation.reload).to be_pending
        expect(claims.spent).to include(:invitation)
        expect(claims.problems).to eq([ :invitation_email_mismatch ])
      end

      it "records :invitation_consumed for a stale invitation without raising" do
        user = create(:user)
        invitation = create(:invitation, :expired, email: user.email_address)
        claims = described_class.new(invitation_token: invitation.token)

        expect { claims.claim(user) }.not_to raise_error

        expect(claims.spent).to include(:invitation)
        expect(claims.problems).to eq([ :invitation_consumed ])
      end
    end

    describe "join-link digest" do
      before do
        permit_open_join_links
      end

      it "admits the user through an active link and spends the digest" do
        user = create(:user)
        ensure_member_role
        workspace = create(:workspace, :open_link)
        link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
        digest = WorkspaceJoinLink.digest(link.plaintext_token)
        claims = described_class.new(join_digest: digest)

        claims.claim(user)

        expect(user.workspaces).to include(workspace)
        expect(claims.spent).to include(:join)
        expect(claims.problems).to be_empty
      end

      it "silently spends a revoked link's digest" do
        user = create(:user)
        ensure_member_role
        workspace = create(:workspace, :open_link)
        link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
        digest = WorkspaceJoinLink.digest(link.plaintext_token)
        link.revoke!
        claims = described_class.new(join_digest: digest)

        claims.claim(user)

        expect(user.workspaces).not_to include(workspace)
        expect(claims.spent).to include(:join)
        expect(claims.problems).to be_empty
      end

      # #952: the digest-parked (deferred-OAuth) path is the other caller
      # of WorkspaceJoinLink#admit; expiry was untested through it.
      it "silently spends an expired link's digest, same as a revoked one" do
        user = create(:user)
        ensure_member_role
        workspace = create(:workspace, :open_link)
        link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
        digest = WorkspaceJoinLink.digest(link.plaintext_token)
        claims = described_class.new(join_digest: digest)

        travel_to 8.days.from_now do
          claims.claim(user)
        end

        expect(user.workspaces).not_to include(workspace)
        expect(claims.spent).to include(:join)
        expect(claims.problems).to be_empty
      end

      it "records :join_link_at_capacity without raising when the workspace is full" do
        user = create(:user)
        member_role = ensure_member_role
        workspace = create(:workspace, :open_link)
        link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
        digest = WorkspaceJoinLink.digest(link.plaintext_token)
        workspace.update!(max_members: 1)
        create(:membership, workspace: workspace, user: create(:user), role: member_role)
        claims = described_class.new(join_digest: digest)

        expect { claims.claim(user) }.not_to raise_error

        expect(user.workspaces).not_to include(workspace)
        expect(claims.spent).to include(:join)
        expect(claims.problems).to eq([ :join_link_at_capacity ])
      end
    end
  end
end
