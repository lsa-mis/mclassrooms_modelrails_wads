# "Invitations from inviter I to address E are not delivered." Email-keyed and
# account-independent: works for a decliner with no account, survives the address
# becoming a user, does not follow a user who changes address (PR 4 spec §2).
class InvitationBlock < ApplicationRecord
  belongs_to :inviter, class_name: "User"

  # Deliberately NOT Tenanted: an inviter-to-address relationship spans every
  # workspace the inviter can invite from (PR 4 spec §5).
  # Deliberately NOT Trackable: any activity row the inviter could read is a
  # block oracle (invariant I3); the system's record of a block is the block.
  normalizes :email, with: ->(e) { EmailNormalizer.normalize(e) }
  encrypts :email, deterministic: true, downcase: true
  validates :email, presence: true, format: { with: User::EMAIL_FORMAT },
            uniqueness: { scope: :inviter_id }

  # The one write (PR 4 spec §5.1): insert idempotently, stamp the inviter's
  # live invitations to the address, sweep the invitee's notification rows —
  # one transaction, in that order.
  def self.block!(inviter:, email:)
    transaction do
      block = find_or_create_block(inviter, email)
      suppress_pending_invitations_from(inviter, email)
      sweep_invitee_notifications(inviter, email)
      block
    end
  end

  def self.find_or_create_block(inviter, email)
    find_or_create_by!(inviter: inviter, email: email)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # The uniqueness race signals either way on this serialized-writer DB: the
    # index, or the validation seeing the winner's committed row. A genuinely
    # invalid email cannot reach here (callers pass a persisted invitation's
    # validated address); find_by!'s RecordNotFound is the loud backstop.
    find_by!(inviter: inviter, email: email)
  end
  private_class_method :find_or_create_block

  def self.suppress_pending_invitations_from(inviter, email)
    now = Time.current
    rows = inviter.sent_invitations.pending.where(email: email, suppressed_at: nil).to_a
    # Row by row, no batching: a collision inside one UPDATE would abort the
    # whole block, and batching in a transaction holds the writer lock without
    # releasing it. Bounded: one inviter, one address, pending only — and
    # pending_live guarantees pairwise-distinct invitables, so rows collide
    # only with a pre-existing ghost, never each other (PR 4 spec §5.1).
    rows.each do |row|
      # The ROUTINE case, not a race: re-inviting a suppressed address mints a
      # fresh live row beside the old ghost, so a pre-existing ghost for this
      # (email, invitable, inviter) is the ordinary shape here. Skipping it is
      # what keeps the common path off the index; the rescue below is the narrow
      # TOCTOU backstop for a ghost that lands between this check and the write.
      next if Invitation.pending.where.not(suppressed_at: nil).exists?(
        email: email, invitable_type: row.invitable_type,
        invitable_id: row.invitable_id, invited_by_id: inviter.id
      )
      begin
        row.update_column(:suppressed_at, now) # callback-free — invariant I4
      rescue ActiveRecord::RecordNotUnique
        # A ghost won the slot between the check and the write. update_columns
        # wrote the cast value into @attributes and cleared the dirty flag
        # BEFORE the DB refused, so there is no recorded change to restore;
        # reload takes value and clean state back from the still-live row.
        # Safe here because the rows came straight from a fresh `to_a` and
        # carry no unsaved changes. Skip this row, continue the loop.
        row.reload
      end
    end
  end
  private_class_method :suppress_pending_invitations_from

  def self.sweep_invitee_notifications(inviter, email)
    invitee = User.find_by(email_address: email)
    return unless invitee
    # Subquery form — delete_all on a joined relation does not work on SQLite.
    # Never the inviter's rows (invariant I1).
    invitee.notifications.where(
      event_id: Noticed::Event.where(
        record_type: "Invitation",
        record_id: inviter.sent_invitations.where(email: email).select(:id)
      ).select(:id)
    ).delete_all
  end
  private_class_method :sweep_invitee_notifications
end
