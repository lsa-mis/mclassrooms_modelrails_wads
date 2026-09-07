require "rails_helper"

# The core's examples; each trait's live beside it under spec/models/invitation/.
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
      expect(Invitation.acceptable).to contain_exactly(pending_inv)
    end

    it "excludes expired from the acceptable scope" do
      create(:invitation, :expired)
      expect(Invitation.acceptable).to be_empty
    end

    # #452: the enum generates BOTH a `pending` scope and a `pending?`
    # predicate, and overriding only the scope to also require an unexpired
    # `expires_at` made the two disagree — an expired invitation was `pending?`
    # but absent from `Invitation.pending`. Anyone reasoning "in the scope iff
    # the predicate" wrote a subtle bug. The extra constraint now lives under
    # its own name, which mirrors the `acceptable?` predicate exactly.
    describe "class- and instance-level agreement" do
      let!(:expired) { create(:invitation, :expired) }

      it "keeps the enum-generated pending scope in step with pending?" do
        expect(expired).to be_pending
        expect(Invitation.pending).to include(expired)
      end

      it "mirrors acceptable? with the acceptable scope" do
        expect(expired).not_to be_acceptable
        expect(Invitation.acceptable).not_to include(expired)

        open_invite = create(:invitation)
        expect(open_invite).to be_acceptable
        expect(Invitation.acceptable).to include(open_invite)
      end

      it "keeps has_invitee? the exact complement of magic_link? (PR 4)" do
        emailed = create(:invitation)
        bearer = create(:invitation, :magic_link)
        expect(emailed.has_invitee?).to eq(!emailed.magic_link?)
        expect(bearer.has_invitee?).to eq(!bearer.magic_link?)
      end
    end
  end

  describe "Invitation::NotAcceptable" do
    it "is a standalone StandardError (not an ActiveRecord::RecordInvalid)" do
      expect(Invitation::NotAcceptable.ancestors).to include(StandardError)
      expect(Invitation::NotAcceptable.ancestors).not_to include(ActiveRecord::RecordInvalid)
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
      expect { invitation.decline! }.to raise_error(ActiveRecord::RecordInvalid) { |e|
        expect(e.record.errors.details[:base]).to include(error: :already_processed)
      }
    end
  end

  describe "#revoke! guard" do
    it "prevents revoking an already declined invitation" do
      invitation = create(:invitation)
      invitation.decline!
      expect { invitation.revoke! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  # #675: the guards must re-read state INSIDE the transaction (accept!'s
  # lock! shape) — a stale in-memory pending? passing the guard would write
  # revoked/declined OVER a committed acceptance, leaving a revoked invitation
  # with a live membership and an audit trail that lies.
  describe "check-then-act races (#675)" do
    let(:invitation) { create(:invitation, invitable: create(:workspace)) }

    it "revoke! on a stale instance cannot overwrite a committed acceptance" do
      stale = Invitation.find(invitation.id)
      invitation.accept!(create(:user))

      expect { stale.revoke! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(invitation.reload.status).to eq("accepted")
    end

    it "decline! on a stale instance cannot overwrite a committed acceptance" do
      stale = Invitation.find(invitation.id)
      invitation.accept!(create(:user))

      expect { stale.decline! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(invitation.reload.status).to eq("accepted")
    end

    it "resend! refuses a non-pending invitation instead of rotating its token" do
      invitation.accept!(create(:user))
      original_token = invitation.reload.token

      expect { invitation.resend! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(invitation.reload.token).to eq(original_token)
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

  describe "email normalization" do
    let(:workspace) { create(:workspace) }

    it "stores the canonical form of the address" do
      invitation = create(:invitation, invitable: workspace, email: "Invitee@Example.COM")
      expect(invitation.email).to eq("invitee@example.com")
    end

    it "accepts an address padded with whitespace" do
      invitation = build(:invitation, invitable: workspace, email: " invitee@example.com ")
      expect(invitation).to be_valid
      expect(invitation.email).to eq("invitee@example.com")
    end

    it "stores an IDN domain in its punycode form, matching User" do
      invitation = create(:invitation, invitable: workspace, email: "user@bücher.de")
      expect(invitation.email).to eq("user@xn--bcher-kva.de")
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

  # Wiring coverage: drive accept!/decline! and assert the notifier fires.
  # The notifiers themselves are specced in spec/notifiers/; without these,
  # the after_update_commit registrations could be deleted and the suite
  # would stay green.
  describe "notification wiring" do
    let(:workspace) { create(:workspace) }
    let(:inviter) { create(:user) }
    let(:invitation) { create(:invitation, invitable: workspace, invited_by: inviter, email: "invitee@example.com") }

    def recipients_of(notifier_type)
      Noticed::Notification.where(type: "#{notifier_type}::Notification").map(&:recipient)
    end

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

    # Actor exclusion across the two notifiers that fire on one acceptance.
    # Before this, an owner-inviter got BOTH "Alan joined" and "alan@…
    # accepted your invitation" for the same event.
    describe "accepted — actor exclusion across both notifiers" do
      include ActiveJob::TestHelper

      it "gives an owner-inviter only the acceptance notice, and the invitee the member-added one" do
        ada = create(:user)
        create(:membership, :owner, user: ada, workspace: workspace)
        alan = create(:user)
        alan_email = alan.email_address
        invite = create(:invitation, invitable: workspace, invited_by: ada, email: alan_email)
        Noticed::Notification.delete_all
        Noticed::Event.delete_all
        ActionMailer::Base.deliveries.clear
        clear_enqueued_jobs

        invite.accept!(alan)
        perform_enqueued_jobs(only: Noticed::EventJob)
        perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
        perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)

        expect(recipients_of("WorkspaceMemberAddedNotifier")).to eq([ alan ])
        expect(recipients_of("WorkspaceInvitationAcceptedNotifier")).to eq([ ada ])
        # The invitee still gets the welcome email; the inviter gets no email
        # for an event she performed herself.
        expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq([ alan_email ])
      end

      it "keeps owners notified and the inviter thanked when a non-owner admin invited" do
        ada = create(:user)
        create(:membership, :owner, user: ada, workspace: workspace)
        edith = create(:user)
        create(:membership, :admin, user: edith, workspace: workspace)
        barb = create(:user)
        invite = create(:invitation, invitable: workspace, invited_by: edith, email: barb.email_address)
        Noticed::Notification.delete_all
        Noticed::Event.delete_all

        invite.accept!(barb)

        expect(recipients_of("WorkspaceMemberAddedNotifier")).to contain_exactly(barb, ada)
        expect(recipients_of("WorkspaceInvitationAcceptedNotifier")).to eq([ edith ])
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

  describe "activity workspace attribution" do
    it "records the invitation's resolved workspace even when Current.workspace is a different workspace" do
      workspace = create(:workspace)
      other_workspace = create(:workspace)
      Current.workspace = other_workspace

      invitation = create(:invitation, invitable: workspace)

      log = ActivityLog.where(trackable: invitation, action: "invitation.created").last
      expect(log.workspace).to eq(workspace)
    ensure
      Current.workspace = nil
    end
  end
end
