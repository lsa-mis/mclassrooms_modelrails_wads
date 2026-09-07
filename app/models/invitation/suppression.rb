class Invitation < ApplicationRecord
  # Delivery suppression for invitations whose invitee has blocked the inviter,
  # and the "Don't invite me again" token that creates the block.
  # See /docs/developer/security (Invitation blocks).
  module Suppression
    extend ActiveSupport::Concern

    # Payload is `status`, so accept/decline/block/revoke kill the token; a resend rotates the bearer token, not this (#951).
    BLOCK_TOKEN_LIFETIME = 7.days

    included do
      scope :unsuppressed, -> { where(suppressed_at: nil) }

      generates_token_for :block_confirmation, expires_in: BLOCK_TOKEN_LIFETIME do
        status
      end
    end

    def blocked_by_invitee?
      has_invitee? && InvitationBlock.exists?(inviter_id: invited_by_id, email: email)
    end

    def deliverable? = has_invitee? && !blocked_by_invitee?

    def suppressed? = suppressed_at.present?

    # Stamp first, then record: an unexpected error propagates before any audit row, so the mailer job
    # retries and re-enters the guard.
    def suppress_delivery!(mailer_action:)
      stamp_suppression
      record_suppressed_delivery(mailer_action)
    end

    def decline_and_block!
      # ArgumentError, deliberately never rescued: the controller pre-checks has_invitee?; reaching this is a programmer error.
      raise ArgumentError, "magic-link invitations have no invitee to block for" unless has_invitee?
      # Block commits first, so a lost decline race still records the block; nested, both roll back together.
      InvitationBlock.block!(inviter: invited_by, email: email)
      decline!
    end

    private

    # Callback-free on purpose: Trackable#track_update would publish this stamp to the workspace feed — a block oracle.
    def stamp_suppression
      update_column(:suppressed_at, Time.current) unless suppressed?
    rescue ActiveRecord::RecordNotUnique
      # A sibling ghost already holds the slot — the correct end state. update_column had already written the
      # cast value and cleared the dirty flag before the DB refused, so restore_attributes has nothing to
      # restore; reload takes value and clean state back from the row, which is still live.
      reload
    end

    # Best-effort, admin-visibility, outside Trackable's callbacks (Trackable's header names this writer).
    # Metadata never carries the address: it is unencrypted JSON.
    def record_suppressed_delivery(mailer_action)
      ActivityLog.create!(
        actor: nil, action: "invitation.delivery_suppressed", trackable: self,
        workspace: resolved_workspace, visibility: "admin",
        metadata: { "mailer_action" => mailer_action.to_s }
      )
    rescue StandardError => e
      Rails.logger.warn("Activity tracking failed for Invitation##{id} (delivery_suppressed): #{e.message}")
      Rails.error.report(e, handled: true,
        context: { trackable: "Invitation##{id}", action: "invitation.delivery_suppressed" })
    end
  end
end
