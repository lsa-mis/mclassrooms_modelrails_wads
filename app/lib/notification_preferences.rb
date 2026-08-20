# frozen_string_literal: true

# Wraps the user_preferences.notification_preferences JSONB column with
# typed accessors for the new parallel-list shape (Phase 1 redesign).
#
# JSONB shape:
#   notification_types: { security, account_access, workspace_activity,
#                         billing }  → booleans
#   delivery_methods:   { in_app: { enabled },
#                         email:  { enabled, frequency: instant|daily|weekly } }
#   quiet_hours:        { enabled, start: "HH:MM", end: "HH:MM", allow_urgent }
#   retention_days:     Integer (30/60/90/180/365) or nil ("never")
class NotificationPreferences
  CATEGORIES = %w[security account_access workspace_activity billing].freeze
  # Digest is folded into Email channel's frequency selector — no longer a channel.
  CHANNELS   = %w[in_app email].freeze
  EMAIL_FREQUENCIES = %w[instant daily weekly].freeze
  # Lowercase day names used in quiet_hours.active_days. Matches the output
  # of `Time#strftime("%A").downcase` so day-membership checks are direct
  # string comparisons.
  DAYS_OF_WEEK = %w[monday tuesday wednesday thursday friday saturday sunday].freeze
  SECURITY_CATEGORY = "security"
  # NotificationCleanupJob enforces a 1-year retention floor on security
  # notifications regardless of user preference.
  RETENTION_FLOORS = { "security" => 365.days }.freeze
  # Validation constants used by #merge. Live on the value object (not the
  # controller) because they describe schema semantics.
  HH_MM_REGEX = /\A([01]\d|2[0-3]):([0-5]\d)\z/
  ALLOWED_RETENTION_DAYS = [ 30, 60, 90, 180, 365 ].freeze

  # Raised by #merge when a partial-change hash violates the JSONB schema.
  # Caller catches and responds 422 — see Settings::NotificationPreferencesController#update.
  class InvalidChange < StandardError; end

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

  # Returns true, false, or the :digest sentinel (email deferred to the
  # digest pipeline). Accepts String or Symbol arguments — coerced here so
  # callers never need to know the JSONB blob is string-keyed.
  def allow?(category:, channel:)
    category = category.to_s
    channel  = channel.to_s

    return false unless recognized?(category, channel)
    return security_delivery_allowed?(channel) if security_floor?(category)
    return false unless type_enabled?(category)
    return false unless channel_enabled?(channel)
    return :digest if deferred_to_digest?(channel)
    return false if quiet_hours_active?

    true
  end

  # Whether quiet hours are currently suppressing non-security delivery.
  # Wraps midnight if start > end (e.g., 22:00..07:00). Falls back to
  # Time.zone if the user has no timezone set — never raises.
  #
  # Per-weekday filter via `quiet_hours.active_days`:
  #   - Missing key (legacy data) → behaves as all 7 days active.
  #   - Empty array → quiet hours never active (no days selected).
  #   - Non-empty array → only suppress on listed days. Check is against the
  #     CURRENT calendar day in the user's timezone — overnight windows
  #     (22:00..07:00) on a non-active day get no suppression in the wrap,
  #     even if the time-of-day falls inside the window's wrap portion.
  def quiet_hours_active?(now: Time.current)
    qh = @data["quiet_hours"] || {}
    return false unless qh["enabled"] == true

    zone_name = @user&.preferences&.timezone
    zone = (zone_name && ActiveSupport::TimeZone[zone_name]) || Time.zone

    active_days = qh["active_days"]
    if active_days.is_a?(Array)
      today = zone.now.strftime("%A").downcase
      return false unless active_days.include?(today)
    end

    s = qh["start"] || "22:00"
    e = qh["end"]   || "07:00"

    # The picker's full range (00:00–23:59) means all-day quiet hours. The
    # half-open [s, e) comparison below would otherwise leave a 1-minute hole
    # at 23:59 (DND off) — a real UX gap, and the source of a class of flaky
    # notifier specs that set this window to mean "DND always on".
    return true if s == "00:00" && e == "23:59"

    cur = zone.now.strftime("%H:%M")
    if s <= e
      cur >= s && cur < e
    else
      cur >= s || cur < e
    end
  end

  # Back-compat alias from v1's flat DND boolean.
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

  # Returns a new NotificationPreferences with `changes` validated,
  # coerced, and deep-merged into the underlying JSONB hash. The receiver
  # is unchanged — no half-applied state if validation raises mid-way.
  #
  # `changes` is the parameter shape posted from the preferences form:
  # nested string-keyed hash with values that may need type coercion
  # (the form submits strings; the JSONB column wants booleans / ints /
  # nil for "never" retention).
  #
  # Raises NotificationPreferences::InvalidChange on:
  #   - retention_days not in ALLOWED_RETENTION_DAYS (and not "never"/blank)
  #   - notification_types key outside CATEGORIES
  #   - delivery_methods.email.frequency outside EMAIL_FREQUENCIES
  #   - quiet_hours.start/end not matching HH:MM
  #   - quiet_hours.active_days not an Array, or containing unknown days
  def merge(changes)
    return self if changes.blank?

    prepared = changes.deep_stringify_keys.deep_dup
    validate_and_coerce!(prepared)

    self.class.new(@data.deep_dup.deep_merge!(prepared), user: @user)
  end

  # Whether the given changes would alter digest scheduling (email cadence).
  # Drives the recompute_digest_due_at decision in the controller.
  def digest_changed_by?(changes)
    changes&.dig("delivery_methods", "email", "frequency").present? ||
      changes&.dig(:delivery_methods, :email, :frequency).present?
  end

  private

  def recognized?(category, channel)
    CATEGORIES.include?(category) && CHANNELS.include?(channel)
  end

  # Security bypasses type toggles, digest deferral, and quiet hours.
  def security_floor?(category)
    category == SECURITY_CATEGORY
  end

  # In-app security is always-on; email honors an explicit channel opt-out —
  # a user who disabled email entirely accepts that security alerts won't email.
  def security_delivery_allowed?(channel)
    channel != "email" || @data.dig("delivery_methods", "email", "enabled") != false
  end

  def type_enabled?(category)
    @data.dig("notification_types", category) == true
  end

  def channel_enabled?(channel)
    @data.dig("delivery_methods", channel, "enabled") == true
  end

  # Non-instant email frequency queues for the digest pipeline instead of
  # sending now.
  def deferred_to_digest?(channel)
    channel == "email" && email_frequency != "instant"
  end

  def validate_and_coerce!(changes)
    if changes.key?("retention_days")
      raise InvalidChange unless valid_retention?(changes["retention_days"])
      changes["retention_days"] = normalize_retention(changes["retention_days"])
    end

    if changes.key?("notification_types")
      unknown = changes["notification_types"].keys - CATEGORIES
      raise InvalidChange if unknown.any?
    end

    if (freq = changes.dig("delivery_methods", "email", "frequency"))
      raise InvalidChange unless EMAIL_FREQUENCIES.include?(freq)
    end

    if changes.key?("quiet_hours")
      qh = changes["quiet_hours"]
      raise InvalidChange if qh["start"].present? && !qh["start"].match?(HH_MM_REGEX)
      raise InvalidChange if qh["end"].present?   && !qh["end"].match?(HH_MM_REGEX)
      if qh.key?("active_days")
        days = qh["active_days"]
        raise InvalidChange unless days.is_a?(Array)
        # Strip Rails' hidden-empty-sentinel that the day-picker form always
        # includes so active_days is submitted as an array even when zero
        # boxes are checked. Empty array post-strip = user selected zero
        # days = quiet hours effectively off (value object treats it so).
        days = days.reject(&:blank?)
        raise InvalidChange unless (days - DAYS_OF_WEEK).empty?
        qh["active_days"] = days
      end
    end

    coerce_booleans!(changes)
  end

  # Blank / "never" => valid (means "never auto-delete").
  # Otherwise the integer form must appear in ALLOWED_RETENTION_DAYS.
  def valid_retention?(value)
    return true if value.blank? || value.to_s == "never"
    ALLOWED_RETENTION_DAYS.include?(value.to_i)
  end

  def normalize_retention(value)
    return nil if value.blank? || value.to_s == "never"
    value.to_i
  end

  # Recursively coerce "true"/"false" strings to actual booleans so the
  # JSONB column doesn't get string values for boolean toggles. Also
  # coerces digest.hour_local to integer if numeric-string.
  def coerce_booleans!(hash)
    hash.each do |key, value|
      case value
      when "true"  then hash[key] = true
      when "false" then hash[key] = false
      when Hash    then coerce_booleans!(value)
      else
        hash[key] = value.to_i if key == "hour_local" && value.is_a?(String) && value.match?(/\A\d+\z/)
      end
    end
  end
end
