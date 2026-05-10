# frozen_string_literal: true

# Scheduled job that emits the daily/weekly digest email for users whose
# `digest_next_due_at` has passed. Drives the digest channel of the v1
# notifications stack.
#
# Scope strategy: a single indexed range scan against
# `user_preferences.digest_next_due_at` (the partial index in the migration
# only covers non-NULL values, so users without a digest schedule are
# automatically skipped). No per-user polling.
#
# `seen_at` semantics: when a digest is enqueued for a user, every
# notification included in that digest gets `seen_at` stamped immediately.
# This is the load-bearing dedupe — the next digest cycle's `where(seen_at: nil)`
# filter skips them, so the user never sees the same item in two consecutive
# digests. Trade-off: we mark seen at job-run, not at mail-deliver. If the
# downstream `MailDeliveryJob` fails after this job commits, the user has
# notifications-marked-seen but no email. The in-app badge still shows them
# until the user opens them; missing email is recoverable on the next cycle.
#
# Cadence: every 15 minutes via `config/recurring.yml`. Each user's
# individual cadence (daily/weekly) lives in `notification_preferences.digest`
# and is honored by the `next_due_at_in(timezone)` recompute.
class DigestMailerJob < ApplicationJob
  queue_as :default

  def perform
    User.joins(:preferences)
        .where("user_preferences.digest_next_due_at <= ?", Time.current)
        .find_each do |user|
      send_digest_for(user)
    rescue StandardError => e
      Rails.logger.error("DigestMailerJob failed for user #{user.id}: #{e.class}: #{e.message}")
      # Bump next-due forward by an hour so we skip this cycle but retry
      # on the next pass; avoids tight-loop reruns under persistent errors.
      user.preferences&.update_column(:digest_next_due_at, 1.hour.from_now)
    end
  end

  private

  def send_digest_for(user)
    prefs = user.preferences&.notification_preferences_object
    return reschedule(user, prefs) if prefs.nil?
    return reschedule(user, prefs) if prefs.do_not_disturb? || !prefs.digest_enabled?

    notifications = digest_scope(user).to_a

    if notifications.any?
      NotificationMailer.digest(user, notifications).deliver_later
      mark_included_seen!(notifications)
      user.preferences.update!(digest_last_sent_at: Time.current)
    end

    reschedule(user, prefs)
  end

  def digest_scope(user)
    floor = user.preferences.digest_last_sent_at || 24.hours.ago
    eligible_types = ApplicationNotifier
                       .descendants
                       .select { |c| NotificationPreferences::DIGEST_ELIGIBLE_CATEGORIES.include?(c.category_name) }
                       .map { |c| "#{c.name}::Notification" }

    user.notifications
        .where(seen_at: nil)
        .where(type: eligible_types)
        .where("noticed_notifications.created_at >= ?", floor)
  end

  # Bulk update_all is intentional: bypasses callbacks for speed since
  # mark_seen! on an individual notification only writes the timestamp
  # column anyway. Atomic single UPDATE; no race window.
  def mark_included_seen!(notifications)
    return if notifications.empty?
    Noticed::Notification
      .where(id: notifications.map(&:id))
      .update_all(seen_at: Time.current)
  end

  def reschedule(user, prefs)
    return unless user.preferences && prefs

    tz_name = user.preferences.timezone.presence
    timezone = (tz_name && ActiveSupport::TimeZone[tz_name]) || Time.zone
    user.preferences.update_column(
      :digest_next_due_at,
      prefs.next_due_at_in(timezone)
    )
  end
end
