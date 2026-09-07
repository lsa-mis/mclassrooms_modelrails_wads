class Invitation < ApplicationRecord
  # Redeeming an invitation: one choke point (guard_acceptable!) plus the
  # address-bound consume path both signup flows share. Upstream additionally
  # branches on client/project invitable shapes; this fork has neither
  # domain, so accept! only ever admits to a workspace.
  module Acceptance
    extend ActiveSupport::Concern

    class_methods do
      # Both signup acceptance paths (PendingClaims#claim!, Authentication#claim_pending!) funnel here so their
      # semantics can't diverge: nil when the token matches nothing, NotAcceptable when it does but can't be accepted.
      def consume!(token:, user:, expected_email: nil)
        return if token.blank?

        invitation = find_by(token: token)
        return if invitation.nil?

        # Address-bound redemption: a leaked link can't be claimed from a different proven address;
        # nil-email magic links stay bearer by design. See /docs/developer/security.
        if invitation.email.present? && expected_email.present? &&
            !EmailNormalizer.equivalent?(invitation.email, expected_email)
          raise EmailMismatch
        end

        invitation.accept!(user)
        invitation
      end
    end

    def accept!(user)
      transaction do
        lock!
        guard_acceptable!
        accept_workspace_invitation!(user)

        update!(
          status: "accepted",
          accepted_by: user,
          accepted_at: Time.current
        )
      end
    end

    private

    # One choke point, one generic message on every refusal — an invitee must not learn a workspace is locked.
    def guard_acceptable!
      raise NotAcceptable, "Invitation no longer acceptable" unless pending?
      raise NotAcceptable, "Invitation no longer acceptable" if expired?
      raise NotAcceptable, "Invitation no longer acceptable" unless resolved_workspace&.admittable?
    end

    def accept_workspace_invitation!(user)
      invitable.admit(user, role: role, granted_by: invited_by)
    end
  end
end
