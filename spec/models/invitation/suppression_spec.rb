require "rails_helper"

RSpec.describe "Invitation suppression schema", type: :model do
  include ActiveJob::TestHelper

  let(:workspace) { create(:workspace) }
  let(:inviter) { create(:user) }

  def raw_invitation!(email:, invitable: workspace, invited_by: inviter, suppressed_at: nil)
    inv = build(:invitation, email: email, invitable: invitable, invited_by: invited_by)
    inv.suppressed_at = suppressed_at
    inv.save!(validate: false)
    inv
  end

  describe "invitation_blocks uniqueness (P1 — reaches the index, not the validation)" do
    it "rejects a duplicate (email, inviter) pair at the database" do
      InvitationBlock.insert_all!([ { inviter_id: inviter.id, email: "dup@example.com",
                                      created_at: Time.current, updated_at: Time.current } ])
      expect {
        InvitationBlock.insert_all!([ { inviter_id: inviter.id, email: "dup@example.com",
                                        created_at: Time.current, updated_at: Time.current } ])
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "pending_live slot (P2)" do
    it "rejects two live pending invitations for the same (email, invitable)" do
      raw_invitation!(email: "live@example.com")
      expect { raw_invitation!(email: "live@example.com", invited_by: create(:user)) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "admits the pair when one row is suppressed" do
      raw_invitation!(email: "ghosted@example.com", suppressed_at: Time.current)
      expect { raw_invitation!(email: "ghosted@example.com", invited_by: create(:user)) }
        .not_to raise_error
    end
  end

  describe "pending_ghosts slot (P3)" do
    it "rejects two ghosts for the same (email, invitable, inviter)" do
      raw_invitation!(email: "g@example.com", suppressed_at: Time.current)
      expect { raw_invitation!(email: "g@example.com", suppressed_at: Time.current) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "admits a second ghost from a different inviter" do
      raw_invitation!(email: "g2@example.com", suppressed_at: Time.current)
      expect {
        raw_invitation!(email: "g2@example.com", suppressed_at: Time.current,
                        invited_by: create(:user))
      }.not_to raise_error
    end
  end

  describe "planner uses pending_live (P4 — the scoped query implies the predicate)" do
    it "names index_invitations_pending_live" do
      relation = Invitation.pending.unsuppressed
                           .where(email: "x@example.com", invitable_type: "Workspace", invitable_id: workspace.id)
      # Explained through to_sql, not Relation#explain: SQLite can only prove a
      # query implies a partial index's WHERE when the terms are literals, and
      # #explain runs the statement with bound `?` parameters — under which the
      # planner falls back to index_invitations_on_invitable no matter how the
      # index is defined. to_sql inlines the values, so this asks the planner
      # the question the probe means to ask. Drop `unsuppressed` and it still
      # goes red (same fallback index), which is the probe's teeth.
      plan = ActiveRecord::Base.connection.explain(relation.to_sql)
      expect(plan).to include("index_invitations_pending_live")
    end
  end

  describe "deliverability predicates" do
    it "has_invitee? is the exact complement of magic_link? (T26 half)" do
      expect(create(:invitation)).to have_attributes(has_invitee?: true, magic_link?: false)
      expect(create(:invitation, :magic_link)).to have_attributes(has_invitee?: false, magic_link?: true)
    end

    it "deliverable? is false only for magic links and blocked addresses" do
      open_invite = create(:invitation)
      expect(open_invite).to be_deliverable

      create(:invitation_block, inviter: open_invite.invited_by, email: open_invite.email)
      expect(open_invite).not_to be_deliverable

      expect(create(:invitation, :magic_link)).not_to be_deliverable
    end

    it "keeps the unsuppressed scope in step with suppressed? (T26 half)" do
      live = create(:invitation)
      ghost = create(:invitation, :suppressed)
      expect(live).not_to be_suppressed
      expect(ghost).to be_suppressed
      expect(Invitation.unsuppressed).to include(live)
      expect(Invitation.unsuppressed).not_to include(ghost)
    end
  end

  describe "ghost redeemability (T10, invariant I2)" do
    it "a suppressed invitation is still acceptable by token" do
      ghost = create(:invitation, :suppressed)
      expect(ghost).to be_acceptable
      expect(Invitation.acceptable).to include(ghost)
      expect { Invitation.consume!(token: ghost.token, user: create(:user)) }
        .to change { ghost.reload.status }.from("pending").to("accepted")
    end
  end

  describe "#suppress_delivery! (T17, invariant I4)" do
    let(:invitation) { create(:invitation) }

    it "stamps callback-free: zero new workspace-visible rows" do
      feed = ActivityLog.visible.for_workspace(invitation.resolved_workspace)
                        .where(trackable: invitation)

      expect { invitation.suppress_delivery!(mailer_action: "invite") }
        .not_to change { feed.count }
      expect(Invitation.find(invitation.id)).to be_suppressed
    end

    it "writes exactly one admin row per attempt, with no address in metadata" do
      2.times { invitation.suppress_delivery!(mailer_action: "invite") }

      rows = ActivityLog.where(action: "invitation.delivery_suppressed", trackable: invitation)
      expect(rows.count).to eq(2)
      expect(rows.pluck(:visibility).uniq).to eq([ "admin" ])
      expect(rows.first.workspace_id).to eq(invitation.resolved_workspace.id)
      expect(rows.first.metadata).to eq({ "mailer_action" => "invite" })
      expect(rows.map(&:metadata).map(&:to_json).join).not_to include(invitation.email)
    end

    it "survives a ghost collision: restores the in-memory attribute and still records" do
      # Build order matters: the live row must exist first, then the ghost that
      # already holds the (email, invitable, inviter) ghost slot — so stamping
      # `invitation` collides with pending_ghosts. raw_invitation! bypasses
      # validations, which is the only way to place the ghost second.
      ghost = raw_invitation!(email: invitation.email, invitable: invitation.invitable,
                              invited_by: invitation.invited_by, suppressed_at: Time.current)

      expect { invitation.suppress_delivery!(mailer_action: "invite") }.not_to raise_error
      expect(invitation.suppressed?).to be(false)                    # in-memory un-lied
      expect(Invitation.find(invitation.id)).not_to be_suppressed    # row still live
      expect(ActivityLog.where(action: "invitation.delivery_suppressed",
                               trackable: invitation).count).to eq(1) # the attempt WAS suppressed
      expect(ghost.reload).to be_suppressed
    end
  end

  describe "#decline_and_block!" do
    let(:invitation) { create(:invitation, invited_by: inviter) }

    it "declines once and notifies the inviter exactly once (T7, invariant I1)" do
      expect { invitation.decline_and_block! }
        .to change { Noticed::Event.where(type: "WorkspaceInvitationDeclinedNotifier",
                                          record: invitation).count }.by(1)
      expect(invitation.reload).to be_declined
      expect(InvitationBlock.exists?(inviter_id: inviter.id, email: invitation.email)).to be(true)
    end

    it "refuses a magic-link invitation before any write (T8)" do
      bearer = create(:invitation, :magic_link, invited_by: inviter)
      expect { bearer.decline_and_block! }.to raise_error(ArgumentError)
      expect(InvitationBlock.count).to eq(0)
    end

    it "keeps the block when the decline is raced (T9, #675 shape)" do
      stale = Invitation.find(invitation.id)
      invitation.accept!(create(:user))

      expect { stale.decline_and_block! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(InvitationBlock.exists?(inviter_id: inviter.id, email: invitation.email)).to be(true)
      expect(invitation.reload).to be_accepted
    end
  end

  describe ".bulk_invite! with blocks (T15, T16)" do
    let(:role) { Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" } }

    it "creates a blocked target stamped, counts it sent, and delivers nothing" do
      create(:invitation_block, inviter: inviter, email: "blocked@example.com")

      # Mixed case on purpose: proves Rails `normalizes` applies to the
      # preload's finder values (spec §15's verification, encoded here).
      result = Invitation.bulk_invite!(workspace: workspace,
                                       emails: [ "Blocked@Example.COM", "open@example.com" ],
                                       role: role, invited_by: inviter)

      expect(result).to include(sent: 2, skipped: 0)
      # Create-time gate: asserted before any mailer job can run, so this
      # fails if the create-time stamp is missing — the guard from Task 5
      # only stamps once its job is performed, below.
      expect(Invitation.find_by(email: "blocked@example.com")).to be_suppressed
      # only: — CheckGravatarJob is also queued (enqueued from the user
      # factory behind `inviter`/the invitation_block) and does real
      # network I/O the test suite disallows (house pattern, see
      # workspace_member_added_notifier_spec).
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)
      expect(ActionMailer::Base.deliveries.map(&:to).flatten).to eq([ "open@example.com" ])
    end

    it "collides a blocked re-invite into the existing ghost — skipped, no new row" do
      create(:invitation_block, inviter: inviter, email: "again@example.com")
      Invitation.bulk_invite!(workspace: workspace, emails: [ "again@example.com" ],
                              role: role, invited_by: inviter)

      result = nil
      expect {
        result = Invitation.bulk_invite!(workspace: workspace, emails: [ "again@example.com" ],
                                         role: role, invited_by: inviter)
      }.not_to change { Invitation.where(email: "again@example.com").count }

      # skipped, not sent: no record was created, and counting it sent would
      # make "pending in the index, yet sent:1" an oracle for "blocked"
      # (invariant I3 override of PR 4 spec §6.4 — see commit message).
      expect(result).to include(sent: 0, skipped: 1)
    end

    it "lets an unblocked admin invite an address another inviter ghosted (T16)" do
      create(:invitation, :suppressed, email: "shared@example.com",
             invitable: workspace, invited_by: inviter)
      other_admin = create(:user)

      result = Invitation.bulk_invite!(workspace: workspace, emails: [ "shared@example.com" ],
                                       role: role, invited_by: other_admin)
      expect(result).to include(sent: 1, skipped: 0)
    end
  end

  # Fork: this fork has no single-create-with-immediate-mailer invitation path
  # (workspace invitations only ever go through .bulk_invite! above, which
  # already proves the T15/T16 ghost/block symmetry) — upstream's client-invite
  # variant of this invariant (invite_client!) doesn't apply here.

  # Invitation::Suppression's block-confirmation token, moved from invitation_spec.rb (#1003).
  describe "block confirmation token (#951)" do
    let(:invitation) { create(:invitation) }

    it "round-trips while the invitation is pending" do
      token = invitation.generate_token_for(:block_confirmation)
      expect(Invitation.find_by_token_for(:block_confirmation, token)).to eq(invitation)
    end

    it "dies when the status changes, however it changes" do
      token = invitation.generate_token_for(:block_confirmation)
      invitation.decline!
      expect(Invitation.find_by_token_for(:block_confirmation, token)).to be_nil
    end

    it "survives a resend, which rotates the invitation token but not the invitation" do
      token = invitation.generate_token_for(:block_confirmation)
      invitation.resend!
      expect(Invitation.find_by_token_for(:block_confirmation, token)).to eq(invitation)
    end

    it "expires with the invitation's own lifetime" do
      token = invitation.generate_token_for(:block_confirmation)
      travel_to(Invitation::BLOCK_TOKEN_LIFETIME.from_now + 1.minute) do
        expect(Invitation.find_by_token_for(:block_confirmation, token)).to be_nil
      end
    end
  end
end
