# frozen_string_literal: true

# Emits digest emails (every 15 min) for users whose `digest_next_due_at` has
# passed. `seen_at` is stamped at ENQUEUE, not mail delivery — the load-bearing
# dedupe between cycles — so a downstream mail failure leaves those items
# marked seen with no email sent (the in-app badge still shows them).
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

    notifications = digest_scope(user).to_a

    if notifications.any?
      NotificationMailer.digest(user, notifications).deliver_later
      mark_included_seen!(notifications)
      user.preferences.update!(digest_last_sent_at: Time.current)
    end

    user.preferences.reschedule_digest!
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
end
