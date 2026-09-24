require "rails_helper"

RSpec.describe InvitationBlock, type: :model do
  let(:inviter) { create(:user) }

  describe "validations" do
    it "requires a well-formed email" do
      expect(build(:invitation_block, inviter: inviter, email: "not-an-email")).not_to be_valid
      expect(build(:invitation_block, inviter: inviter, email: "")).not_to be_valid
      expect(build(:invitation_block, inviter: inviter, email: "ok@example.com")).to be_valid
    end

    it "enforces uniqueness per inviter at the validation layer too" do
      create(:invitation_block, inviter: inviter, email: "dup@example.com")
      expect(build(:invitation_block, inviter: inviter, email: "dup@example.com")).not_to be_valid
      expect(build(:invitation_block, inviter: create(:user), email: "dup@example.com")).to be_valid
    end
  end

  describe "encryption (T2)" do
    it "stores ciphertext, not the address" do
      block = create(:invitation_block, inviter: inviter, email: "secret@example.com")
      raw = ActiveRecord::Base.connection.select_value(
        "SELECT email FROM invitation_blocks WHERE id = #{block.id}"
      )
      expect(raw).not_to include("secret@example.com")
      expect(InvitationBlock.find_by(email: "secret@example.com")).to eq(block)
    end

    it "downcases at the cipher on a write that skips the normalizes decoration" do
      # Bare type shares the column's scheme but not its `normalizes` decoration —
      # proves `downcase:` is a cipher-level guarantee, not something `normalizes`
      # provides (design spec §5/T2's "hole" framing is wrong; corrected in this
      # commit's message).
      block = create(:invitation_block, inviter: inviter, email: "placeholder@example.com")
      bare_type = ActiveRecord::Encryption::EncryptedAttributeType.new(
        scheme: InvitationBlock.type_for_attribute(:email).scheme
      )
      ciphertext = bare_type.serialize("MiXeD@Example.COM")
      ActiveRecord::Base.connection.execute(
        "UPDATE invitation_blocks SET email = #{ActiveRecord::Base.connection.quote(ciphertext)} WHERE id = #{block.id}"
      )
      expect(InvitationBlock.find_by(email: "mixed@example.com")).to be_present
    end
  end

  describe "normalization (Ruling T1-1)" do
    it "strips surrounding whitespace before validation and encryption" do
      # Pins the behavior `normalizes` uniquely adds (strip/NFC — see
      # app/lib/email_normalizer.rb) that `downcase:` at the cipher does not cover:
      # without `normalizes`, this padded input fails User::EMAIL_FORMAT outright.
      block = create(:invitation_block, inviter: inviter, email: "  Pad@Example.COM  ")
      expect(InvitationBlock.find_by(email: "pad@example.com")).to eq(block)
    end
  end

  describe "creation writes no activity rows (T27, model half)" do
    it "leaves the ActivityLog table untouched" do
      # Force the let outside the block: create(:user)'s own onboarding
      # (workspace + membership) writes Trackable activity rows of its own.
      inviter
      expect { create(:invitation_block, inviter: inviter, email: "quiet@example.com") }
        .not_to change(ActivityLog, :count)
    end
  end

  describe ".block! (T3, T4, T5, T6)" do
    let(:workspace) { create(:workspace) }
    let(:invitation) { create(:invitation, invitable: workspace, invited_by: inviter) }

    it "is idempotent under a double submit" do
      expect {
        2.times { described_class.block!(inviter: inviter, email: invitation.email) }
      }.to change(described_class, :count).by(1)
    end

    it "absorbs the two-instance uniqueness race, whichever signal fires (T3)" do
      # The loser of a find_or_create_by! race sees RecordInvalid (validation
      # reads the winner's committed row) or RecordNotUnique (the index).
      # Force each branch by stubbing the first lookup to miss.
      described_class.block!(inviter: inviter, email: "raced@example.com")
      allow(described_class).to receive(:find_or_create_by!)
        .and_raise(ActiveRecord::RecordNotUnique)
      expect(described_class.block!(inviter: inviter, email: "raced@example.com"))
        .to eq(described_class.find_by(inviter: inviter, email: "raced@example.com"))

      allow(described_class).to receive(:find_or_create_by!)
        .and_raise(ActiveRecord::RecordInvalid.new(described_class.new))
      expect(described_class.block!(inviter: inviter, email: "raced@example.com"))
        .to eq(described_class.find_by(inviter: inviter, email: "raced@example.com"))
    end

    it "retroactively stamps this inviter's pending invitations to the address, and only theirs (T4)" do
      travel_to(Time.zone.local(2026, 9, 1, 12)) do
        other_invitable = create(:invitation, email: "target@example.com",
                                 invitable: create(:workspace), invited_by: inviter)
        same = create(:invitation, email: "target@example.com",
                      invitable: workspace, invited_by: inviter)
        strangers = create(:invitation, email: "target@example.com",
                           invitable: create(:workspace), invited_by: create(:user))

        described_class.block!(inviter: inviter, email: "target@example.com")

        expect(Invitation.find(same.id)).to be_suppressed
        expect(Invitation.find(other_invitable.id)).to be_suppressed
        expect(Invitation.find(strangers.id)).not_to be_suppressed
      end
    end

    it "skips a colliding stamp and continues to later rows (T4)" do
      live = create(:invitation, email: "collide@example.com",
                    invitable: workspace, invited_by: inviter)
      # The ghost already holds the (email, invitable, inviter) ghost slot, so
      # stamping `live` would collide. Placed second on purpose — that is the
      # order the pending_live/pending_ghosts pair admits.
      create(:invitation, :suppressed, suppressed_at: 1.hour.ago, email: "collide@example.com",
             invitable: workspace, invited_by: inviter)
      later = create(:invitation, email: "collide@example.com",
                     invitable: create(:workspace), invited_by: inviter)

      expect { described_class.block!(inviter: inviter, email: "collide@example.com") }
        .not_to raise_error
      expect(Invitation.find(live.id)).not_to be_suppressed   # ghost holds the slot
      expect(Invitation.find(later.id)).to be_suppressed      # loop continued
    end

    it "sweeps only the invitee's notification rows for this inviter's invitations (T5)" do
      invitee = create(:user, email_address: invitation.email)
      WorkspaceInvitationExpiringSoonNotifier.with(record: invitation).deliver(invitee)
      # Two survivors: the invitee's row for a different address, and the
      # inviter's own row about THIS invitation — deleting the latter would
      # itself be the tell (invariant I1).
      other_address = create(:invitation, invitable: create(:workspace), invited_by: inviter)
      WorkspaceInvitationExpiringSoonNotifier.with(record: other_address).deliver(invitee)
      WorkspaceInvitationResentNotifier.with(record: invitation).deliver(inviter)

      expect { described_class.block!(inviter: inviter, email: invitation.email) }
        .to change { invitee.notifications.count }.by(-1)
      expect(inviter.notifications.count).to be >= 1   # inviter's rows survive
    end

    it "works for an address with no account (T6)" do
      create(:invitation, email: "noaccount@example.com", invitable: workspace, invited_by: inviter)
      expect { described_class.block!(inviter: inviter, email: "noaccount@example.com") }
        .to change(described_class, :count).by(1)
    end
  end

  # #812. Unblocking was a two-statement console recipe, and the second
  # statement is the one that gets forgotten: destroying the block alone leaves
  # the stamped invitation invisible to `bulk_invite!`'s duplicate check, which
  # skips only UNSUPPRESSED pending rows — so every later invite to that
  # address mints another pending duplicate. One transaction, one method.
  describe ".unblock!" do
    let(:workspace) { create(:workspace) }

    it "removes the block and clears the stamps this inviter set on that address" do
      invitation = create(:invitation, email: "undo@example.com", invitable: workspace, invited_by: inviter)
      described_class.block!(inviter: inviter, email: "undo@example.com")
      expect(invitation.reload.suppressed_at).to be_present

      expect { described_class.unblock!(inviter: inviter, email: "undo@example.com") }
        .to change(described_class, :count).by(-1)

      expect(invitation.reload.suppressed_at).to be_nil
    end

    # The asymmetry that makes the second statement easy to forget: a stamp can
    # outlive its block row (an earlier unblock that cleared only the block), so
    # the method must not depend on finding one.
    it "clears a stamp whose block row is already gone" do
      invitation = create(:invitation, email: "orphan@example.com", invitable: workspace, invited_by: inviter)
      described_class.block!(inviter: inviter, email: "orphan@example.com")
      described_class.where(inviter: inviter, email: "orphan@example.com").delete_all

      described_class.unblock!(inviter: inviter, email: "orphan@example.com")

      expect(invitation.reload.suppressed_at).to be_nil
    end

    it "leaves another inviter's block and stamps alone" do
      other_inviter = create(:user)
      mine = create(:invitation, email: "shared@example.com", invitable: workspace, invited_by: inviter)
      theirs = create(:invitation, email: "shared@example.com", invitable: create(:workspace), invited_by: other_inviter)
      described_class.block!(inviter: inviter, email: "shared@example.com")
      described_class.block!(inviter: other_inviter, email: "shared@example.com")

      described_class.unblock!(inviter: inviter, email: "shared@example.com")

      expect(mine.reload.suppressed_at).to be_nil
      expect(theirs.reload.suppressed_at).to be_present
      expect(described_class.exists?(inviter: other_inviter, email: "shared@example.com")).to be(true)
    end

    it "is idempotent when there is nothing to undo" do
      expect { described_class.unblock!(inviter: inviter, email: "never@example.com") }
        .not_to change(described_class, :count)
    end

    # Same reason the stamping writes are callback-free (invariant I4):
    # clearing the flag is not a workspace-feed event, and an activity row an
    # inviter could read is a block oracle.
    it "writes no activity rows" do
      create(:invitation, email: "quiet@example.com", invitable: workspace, invited_by: inviter)
      described_class.block!(inviter: inviter, email: "quiet@example.com")

      expect { described_class.unblock!(inviter: inviter, email: "quiet@example.com") }
        .not_to change(ActivityLog, :count)
    end
  end
end
