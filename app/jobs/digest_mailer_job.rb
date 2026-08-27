# frozen_string_literal: true

# Emits digest emails (every 15 min) for users whose `digest_next_due_at` has
# passed.
#
# The cycle window is HALF-OPEN: `cycle_started_at` is captured before the
# SELECT, the scope takes `created_at >= floor AND created_at < cycle_started_at`,
# and that same value becomes the next floor. No gap, no overlap — a
# notification that arrives while this cycle's mail is being built sits above
# the new watermark and lands in the next digest, rather than falling below a
# watermark stamped after delivery and never being selected at all.
#
# What suppresses a digest item is the recipient READING it, not this job
# marking it. Deduping against the job's own bookkeeping is what emailed people
# things they had already read.
#
# The mailer receives ids, not records: an AR object serialises as a GlobalID,
# and one row deleted by retention between enqueue and render raises
# DeserializationError and dead-letters the whole digest. The mailer re-queries
# those ids at delivery time, which is also the last gate on read state.
# See /docs/developer/notifications (DigestMailerJob).
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
    return if prefs.nil?
    return user.preferences.reschedule_digest! if prefs.do_not_disturb? || !prefs.digest_enabled?

    cycle_started_at = Time.current
    ids = digest_scope(user, cycle_started_at).pluck(:id)

    if ids.any?
      NotificationMailer.digest(user, ids).deliver_later
      user.preferences.update!(digest_last_sent_at: cycle_started_at)
    end

    user.preferences.reschedule_digest!
  end

  def digest_scope(user, cycle_started_at)
    floor = user.preferences.digest_last_sent_at || 24.hours.ago
    # v2: every category except security is digestable when the user has
    # email.frequency != "instant". Security always goes instant (per spec
    # decision #7), so exclude it from the digest scope here. The v1
    # DIGEST_ELIGIBLE_CATEGORIES allow-list was replaced by a security-only
    # exclude-list because v2's "user opts into digest" gate moved up to
    # `prefs.digest_enabled?` (checked in send_digest_for).
    excluded_types = ApplicationNotifier.notification_types_for("security")

    user.notifications
        .where(read_at: nil)
        .where.not(type: excluded_types)
        .where("noticed_notifications.created_at >= ?", floor)
        .where("noticed_notifications.created_at < ?", cycle_started_at)
  end
end
