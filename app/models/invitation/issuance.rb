class Invitation < ApplicationRecord
  # Issuing an invitation: the single-create paths, the bulk form's
  # parsing and cap, and the duplicate rule they all share.
  module Issuance
    extend ActiveSupport::Concern

    MAX_EMAILS_PER_SUBMISSION = 20

    ParsedEmailList = Data.define(:emails, :over_limit) do
      def over_limit? = over_limit
      def empty? = emails.empty?
    end

    class_methods do
      # `pending`, not `acceptable`: narrowing it reopens a blocked-vs-unblocked oracle (invariant I3).
      # See /docs/developer/security (Invitation blocks).
      def already_invited?(invitable:, email:, invited_by:)
        existing = invitable.invitations.pending.where(email: normalize_value_for(:email, email))
        existing.unsuppressed.exists? || existing.where(invited_by: invited_by).exists?
      end

      def parse_email_list(emails)
        all = Array(emails).flat_map { |chunk| chunk.to_s.split(/[\n,]/) }.map(&:strip).reject(&:blank?)

        ParsedEmailList.new(
          emails: all.first(MAX_EMAILS_PER_SUBMISSION),
          over_limit: all.size > MAX_EMAILS_PER_SUBMISSION
        )
      end

      # `sent` counts records created; delivery is asynchronous and may be suppressed.
      def bulk_invite!(workspace:, emails:, role:, invited_by:)
        parsed = parse_email_list(emails)
        emails = parsed.emails
        sent = 0
        skipped = 0

        existing_members = workspace.memberships.kept.joins(:user).pluck(:email_address).to_set
        # unsuppressed: a ghost must not make an unblocked admin skip the address.
        existing_invites = workspace.invitations.acceptable.unsuppressed.where.not(email: nil).pluck(:email).to_set
        # Bounded to this submission (≤ MAX_EMAILS_PER_SUBMISSION); `normalizes`
        # applies to the finder values, so raw input matches stored rows.
        blocked = InvitationBlock.where(inviter: invited_by, email: emails).pluck(:email).to_set

        emails.each do |email|
          normalized = normalize_value_for(:email, email)

          unless normalized.to_s.match?(User::EMAIL_FORMAT)
            skipped += 1
            next
          end

          if existing_members.include?(normalized) || existing_invites.include?(normalized)
            skipped += 1
            next
          end

          begin
            invitation = workspace.invitations.create!(
              email: normalized,
              role: role,
              invited_by: invited_by,
              expires_at: 7.days.from_now,
              suppressed_at: (Time.current if blocked.include?(normalized))
            )
          rescue ActiveRecord::RecordNotUnique
            # Both collision shapes count `skipped`: neither created a record, and counting a ghost as
            # sent is the blocked-address oracle. See /docs/developer/security (Invitation blocks).
            skipped += 1
            next
          end
          existing_invites.add(normalized)
          InvitationMailer.with(invitation: invitation).invite.deliver_later
          sent += 1
        end

        { sent: sent, skipped: skipped, over_limit: parsed.over_limit? }
      end
    end
  end
end
