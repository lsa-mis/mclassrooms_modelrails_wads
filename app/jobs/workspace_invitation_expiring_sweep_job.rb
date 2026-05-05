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
#   - Magic-link invitations (email is nil) — there's no specific recipient.
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
        next if invitation.email.blank?
        invitee = User.find_by(email_address: invitation.email)
        next unless invitee
        WorkspaceInvitationExpiringSoonNotifier.with(record: invitation).deliver(invitee)
      end
  end
end
