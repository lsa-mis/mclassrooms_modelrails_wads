module Workspaces
  module Invitations
    # Resending an invitation: rotate the token, then the invitee email (always)
    # and the inviter's in-app confirmation (deduplicated per minute).
    class ResendsController < ApplicationController
      include WorkspaceScoped

      rate_limit to: 10, within: 3.minutes, only: :create,
        by: -> { Current.user&.id || request.remote_ip },
        with: -> { redirect_to workspace_members_path(@workspace), alert: t("workspaces.invitations.resends.create.rate_limited") }

      def create
        invitation = @workspace.invitations.find(params[:invitation_id])
        authorize invitation, :resend?
        invitation.resend!
        if invitation.magic_link?
          redirect_to workspace_members_path(@workspace),
            notice: t(".magic_link_refreshed"),
            flash: { magic_link_url: accept_invitation_url(token: invitation.token) }
        else
          # Invitee email path is unconditional — the dedup sentinel only
          # gates the in-app confirmation surface for the inviter.
          InvitationMailer.with(invitation: invitation).invite.deliver_later

          # Branch the flash on the sentinel return from
          # ApplicationNotifier#deliver. :delivered means the in-app
          # confirmation row was inserted; :deduplicated means the same
          # (invitation, inviter, minute-bucket) tuple already exists in
          # noticed_events.idempotency_key — i.e. the inviter is double-clicking
          # within the 1-minute window.
          #
          # The third sentinel, :skipped (#928), is unreachable here: it needs an
          # empty recipient set, and `invited_by` is a required belongs_to over a
          # NOT NULL FK column. Were it ever reachable it would fall to
          # ".resent", which is the honest copy — the invitee email above went
          # out regardless of whether an in-app confirmation row was written.
          # Invitation's own `return if invited_by.blank?` guards on the sibling
          # accepted/declined dispatches are belt-and-braces against a stale
          # in-memory record, not evidence that the association can be blank on a
          # persisted row — the FK and the presence validation both say it cannot.
          result = WorkspaceInvitationResentNotifier
            .with(record: invitation)
            .deliver(invitation.invited_by)

          notice_key = (result == :deduplicated) ? ".recently_sent" : ".resent"
          redirect_to workspace_members_path(@workspace), notice: t(notice_key)
        end
      end
    end
  end
end
