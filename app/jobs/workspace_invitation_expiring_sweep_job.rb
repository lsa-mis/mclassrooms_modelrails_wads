# frozen_string_literal: true

# Scheduled sweep that fires `WorkspaceInvitationExpiringSoonNotifier` for every
# pending invitation whose `expires_at` falls within the next 24 hours.
#
# Cadence: every 6 hours (see `config/recurring.yml`). Combined with the
# Notifier's day-bucket idempotency override, each in-window invitation
# produces at most one notification per day until the recipient accepts,
# declines, or the invitation expires and falls out of the window.
#
# Skips:
#   - Invitations that are not deliverable — magic links (no address) and
#     blocked addresses. Blocked skips are silent by design: no stamp, no
#     audit row here (PR 4 spec §7). The recorded sites are `InvitationMailer`'s
#     — this sweep's own mail leg, `NotificationMailer`, skips silently too.
#   - Invitations whose email doesn't resolve to a registered User. The
#     notification is in-app + email; if the recipient doesn't have an
#     account we have no in-app surface to deliver to. The original
#     InvitationMailer.invite already handled the "stranger gets invited"
#     case at create time.
class WorkspaceInvitationExpiringSweepJob < ApplicationJob
  queue_as :default

  def perform
    Invitation
      .where(accepted_at: nil, declined_at: nil)
      .where("expires_at BETWEEN ? AND ?", Time.current, 24.hours.from_now)
      .find_each do |invitation|
        next unless invitation.deliverable?
        invitee = User.find_by(email_address: invitation.email)
        next unless invitee
        WorkspaceInvitationExpiringSoonNotifier.with(record: invitation).deliver(invitee)
      end
  end
end
