# frozen_string_literal: true

# Computes a user's unread-notification bell state — total count plus the
# single dominant severity — from one DB hit (User#unread_notification_breakdown).
# Shared by NotificationBellHelper (view rendering) and NotificationBroadcaster
# (Turbo Stream refreshes, which have no view-helper context).
class UnreadNotificationSummary
  # Higher rank wins when multiple severities are unread.
  SEVERITY_RANK = { danger: 4, warning: 3, info: 2, success: 1 }.freeze

  def initialize(user)
    @user = user
  end

  # The summary hash consumed by the bell partials and broadcast locals.
  def to_h
    { count: count, severity: severity }
  end

  def count
    breakdown.values.sum
  end

  def severity
    return nil if breakdown.empty?

    breakdown.keys
      .map { severity_for(_1) }
      .max_by { SEVERITY_RANK.fetch(_1) }
  end

  private

  attr_reader :user

  def breakdown
    @breakdown ||= user.unread_notification_breakdown
  end

  def severity_for(notifier_class_name)
    case notifier_class_name.safe_constantize
    in nil
      Rails.logger.warn("Stale notifier class in unread notifications: #{notifier_class_name}")
      :info
    in notifier_class
      notifier_class.severity_name || :info
    end
  end
end
