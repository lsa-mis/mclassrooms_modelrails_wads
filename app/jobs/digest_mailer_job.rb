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
    # Per-user fault isolation: one user's malformed prefs or transient mail
    # failure must not abort processing for the other N-1 users in the
    # cycle. StandardError is the right ceiling — Interrupt and SystemExit
    # inherit from Exception (not StandardError), so signals still propagate.
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
    # v2: every category except security is digestable when the user has
    # email.frequency != "instant". Security always goes instant (per spec
    # decision #7), so exclude it from the digest scope here. The v1
    # DIGEST_ELIGIBLE_CATEGORIES allow-list was replaced by a security-only
    # exclude-list because v2's "user opts into digest" gate moved up to
    # `prefs.digest_enabled?` (checked in send_digest_for).
    excluded_types = ApplicationNotifier.notification_types_for("security")

    user.notifications
        .where(seen_at: nil)
        .where.not(type: excluded_types)
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

  # Skip-callbacks via update_column is intentional: reschedule fires every
  # 15 minutes for every digest-eligible user, and we don't want to bump
  # user_preferences.updated_at on each cycle (causes useless cache busts
  # on any view that reads the row's freshness). UserPreferences has no
  # after_update_commit hooks that need to fire here.
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
