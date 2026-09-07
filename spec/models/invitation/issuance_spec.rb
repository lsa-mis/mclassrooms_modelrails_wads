require "rails_helper"

# Invitation::Issuance's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe Invitation, type: :model do
  describe ".bulk_invite!" do
    let(:workspace) { create(:workspace) }
    let(:role) { workspace.effective_roles.first }
    let(:inviter) { create(:user) }

    before do
      create(:membership, :owner, user: inviter, workspace: workspace)
    end

    # Users are stored through EmailNormalizer (IDN domains punycoded), so the
    # dedupe key must be the same normalization — not a bare downcase.
    describe "dedupe against normalized storage" do
      it "skips an existing member typed in the Unicode form of a punycoded address" do
        member = create(:user, email_address: "user@bücher.de")
        create(:membership, user: member, workspace: workspace)

        result = Invitation.bulk_invite!(
          workspace: workspace, emails: [ "user@bücher.de" ], role: role, invited_by: inviter
        )

        expect(result).to include(sent: 0, skipped: 1)
        expect(workspace.invitations.count).to eq(0)
      end

      it "skips a pending invitation typed in the other form of the same IDN address" do
        create(:invitation, invitable: workspace, email: "user@bücher.de", invited_by: inviter)

        result = Invitation.bulk_invite!(
          workspace: workspace, emails: [ "user@xn--bcher-kva.de" ], role: role, invited_by: inviter
        )

        expect(result).to include(sent: 0, skipped: 1)
        expect(workspace.invitations.count).to eq(1)
      end
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

    # C8: the raw textarea string is bulk_invite!'s to parse — both invite
    # forms hand it over verbatim instead of duplicating the split/strip.
    describe "raw-string email list" do
      it "splits on newlines and commas, stripping whitespace" do
        result = Invitation.bulk_invite!(
          workspace: workspace,
          emails: "alice@example.com, bob@example.com\n  carol@example.com  ",
          role: role,
          invited_by: inviter
        )

        expect(result[:sent]).to eq(3)
        expect(result[:skipped]).to eq(0)
        expect(workspace.invitations.pluck(:email))
          .to contain_exactly("alice@example.com", "bob@example.com", "carol@example.com")
      end

      it "ignores blank entries from stray separators" do
        result = Invitation.bulk_invite!(
          workspace: workspace,
          emails: ",\n alice@example.com ,,\n\n",
          role: role,
          invited_by: inviter
        )

        expect(result[:sent]).to eq(1)
        expect(result[:skipped]).to eq(0)
      end

      it "treats an all-separator string as an empty list" do
        result = Invitation.bulk_invite!(
          workspace: workspace,
          emails: " ,\n, ",
          role: role,
          invited_by: inviter
        )

        expect(result).to eq(sent: 0, skipped: 0, over_limit: false)
      end
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
      # The lost race: create the row for real, then stub THIS call's
      # `acceptable` preload to miss it — simulating a commit that lands
      # after the preload reads but before create! — so the real row still
      # trips the pending_live unique index in create!, for real.
      workspace.invitations.create!(
        email: "raced@example.com", role: role, invited_by: inviter,
        expires_at: 7.days.from_now
      )
      invitations = workspace.invitations
      allow(workspace).to receive(:invitations).and_return(invitations)
      allow(invitations).to receive(:acceptable).and_return(Invitation.none)

      result = Invitation.bulk_invite!(
        workspace: workspace,
        emails: [ "raced@example.com", "fresh@example.com" ],
        role: role, invited_by: inviter
      )

      expect(result[:sent]).to eq(1)
      expect(result[:skipped]).to eq(1)
      expect(Invitation.where(email: "raced@example.com").count).to eq(1)
    end
  end

  describe "member-invite role requirement" do
    it "still requires a role for a normal workspace invite" do
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
end
