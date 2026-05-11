# frozen_string_literal: true

# Wraps the user_preferences.notification_preferences JSONB column with
# typed accessors for the new parallel-list shape (Phase 1 redesign).
#
# JSONB shape:
#   notification_types: { security, account_access, workspace_activity,
#                         project_activity, billing }  → booleans
#   delivery_methods:   { in_app: { enabled },
#                         email:  { enabled, frequency: instant|daily|weekly } }
#   quiet_hours:        { enabled, start: "HH:MM", end: "HH:MM", allow_urgent }
#   retention_days:     Integer (30/60/90/180/365) or nil ("never")
#
# Decision tree (allow?):
#   1. category == "security"          → always allow (security floor)
#   2. notification_types[c] == false  → deny
#   3. delivery_methods[ch].enabled    → deny if false
#   4. ch == "email" && freq != "instant" → return :digest sentinel
#   5. quiet_hours_active?(now)        → deny (security exempt via step 1)
#   6. otherwise                       → allow
class NotificationPreferences
  CATEGORIES = %w[security account_access workspace_activity project_activity billing].freeze
  # Digest is folded into Email channel's frequency selector — no longer a channel.
  CHANNELS   = %w[in_app email].freeze
  EMAIL_FREQUENCIES = %w[instant daily weekly].freeze
  SECURITY_CATEGORY = "security"
  # NotificationCleanupJob enforces a 1-year retention floor on security
  # notifications regardless of user preference.
  RETENTION_FLOORS = { "security" => 365.days }.freeze

  # Computed from ApplicationNotifier subclasses; consumed by
  # NotificationCleanupJob to look up which notifier classes carry the
  # security retention floor. Walk lives in one place — see Notifier.
  def self.security_notifier_types
    ApplicationNotifier.notifier_class_names_for(SECURITY_CATEGORY)
  end

  # `user:` is optional but required for quiet_hours_active? to read the
  # user's timezone. Callers that only need allow?/digest_enabled? etc.
  # may pass user: nil.
  def initialize(jsonb_hash, user: nil)
    @data = jsonb_hash || {}
    @user = user
  end

  def allow?(category:, channel:)
    return false unless CATEGORIES.include?(category) && CHANNELS.include?(channel)

    # Step 1: security floor. Always-on for in_app + always-instant for email.
    if category == SECURITY_CATEGORY
      # Honor channel-disabled even for security at the email layer — a
      # user who disabled email entirely accepts that security alerts
      # won't email. In-app remains always-on.
      return false if channel == "email" && @data.dig("delivery_methods", "email", "enabled") == false
      return true
    end

    # Step 2: type disabled
    return false unless @data.dig("notification_types", category) == true

    # Step 3: channel disabled
    return false unless @data.dig("delivery_methods", channel, "enabled") == true

    # Step 4: email frequency non-instant → queue for digest
    if channel == "email"
      freq = @data.dig("delivery_methods", "email", "frequency") || "instant"
      return :digest if freq != "instant"
    end

    # Step 5: quiet hours active (non-security only)
    return false if quiet_hours_active?

    true
  end

  # Whether quiet hours are currently suppressing non-security delivery.
  # Wraps midnight if start > end (e.g., 22:00..07:00). Falls back to
  # Time.zone if the user has no timezone set — never raises.
  def quiet_hours_active?(now: Time.current)
    qh = @data["quiet_hours"] || {}
    return false unless qh["enabled"] == true

    zone_name = @user&.preferences&.timezone
    zone = (zone_name && ActiveSupport::TimeZone[zone_name]) || Time.zone
    cur = zone.now.strftime("%H:%M")
    s = qh["start"] || "22:00"
    e = qh["end"]   || "07:00"

    if s <= e
      # Same-day window: 09:00..17:00 → in-window if s <= cur < e
      cur >= s && cur < e
    else
      # Overnight wrap: 22:00..07:00 → in-window if cur >= s OR cur < e
      cur >= s || cur < e
    end
  end

  # Back-compat alias. The bell button tooltip and any caller asking
  # "is DND currently active?" gets the same boolean as it did under v1.
  # Semantic shift: v1 stored a flat boolean; v2 evaluates time-windowed
  # quiet hours. Callers that wanted "user has set DND-ever" no longer
  # have that concept — only "DND is active right now".
  def do_not_disturb?
    quiet_hours_active?
  end

  def email_frequency
    @data.dig("delivery_methods", "email", "frequency") || "instant"
  end

  def digest_enabled?
    @data.dig("delivery_methods", "email", "enabled") == true &&
      email_frequency != "instant"
  end

  def digest_cadence
    case email_frequency
    when "weekly" then "weekly"
    else "daily"
    end
  end

  # The system picks the hour (8am local). v2 removes user-configurability
  # — the IA shift folded digest controls into email frequency only.
  def digest_hour_local
    8
  end

  def retention_days
    @data["retention_days"]
  end

  def next_due_at_in(timezone)
    now = Time.current.in_time_zone(timezone)
    next_local = timezone.local(now.year, now.month, now.day, digest_hour_local)
    next_local += 1.day if next_local <= now
    next_local += 6.days if digest_cadence == "weekly"
    next_local
  end

  def to_h = @data.deep_dup
end
