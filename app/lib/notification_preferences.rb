# frozen_string_literal: true

# Typed accessors over user_preferences.notification_preferences; the JSONB shape
# is documented in /docs/developer/notifications (its Schema section).
class NotificationPreferences
  CATEGORIES = %w[security account_access workspace_activity billing].freeze
  # Digest is the email channel's frequency, not a channel of its own.
  CHANNELS   = %w[in_app email].freeze
  EMAIL_FREQUENCIES = %w[instant daily weekly].freeze
  # The form of `Time#strftime("%A").downcase`, so day membership is a string comparison.
  DAYS_OF_WEEK = %w[monday tuesday wednesday thursday friday saturday sunday].freeze
  SECURITY_CATEGORY = "security"
  # Schema semantics live on the value object, not the controller.
  HH_MM_REGEX = /\A([01]\d|2[0-3]):([0-5]\d)\z/
  ALLOWED_RETENTION_DAYS = [ 30, 60, 90, 180, 365 ].freeze
  # The reader owns these, not the column default or the migration (PR 5, D9): a rolling
  # deploy or a whole-column save can put a nil back after the backfill.
  DEFAULT_RETENTION_DAYS = 90    # absent key — a row written without the choice
  NEVER_CAP_DAYS = 365           # explicit null — the retired "Never" choice, capped

  # Raised by #merge; the controller answers 422 (Settings::NotificationPreferencesController#update).
  class InvalidChange < StandardError; end

  # `user:` is optional: quiet_hours_active? and next_due_at read its timezone; nothing else does.
  def initialize(jsonb_hash, user: nil)
    @data = jsonb_hash || {}
    @user = user
  end

  # "Send through this channel right now." A false answer says nothing about why;
  # a caller that cares about the digest case asks defer_to_digest?.
  def deliver_now?(category:, channel:)
    allow?(category: category, channel: channel) == true
  end

  # "Email is queued for the digest instead of sending now." Never true for in_app or security.
  def defer_to_digest?(category:, channel:)
    allow?(category: category, channel: channel) == :digest
  end

  # Wraps midnight when start > end; falls back to Time.zone. active_days: a missing key means
  # all seven (legacy rows), an empty list means never, checked against today in the user's zone.
  def quiet_hours_active?(now: Time.current)
    qh = @data["quiet_hours"] || {}
    return false unless qh["enabled"] == true

    zone = user_time_zone
    return false unless quiet_day?(qh["active_days"], zone)

    s = qh["start"] || "22:00"
    e = qh["end"]   || "07:00"

    # The picker's full range means all day; the half-open compare below would leave a
    # one-minute hole at 23:59.
    return true if s == "00:00" && e == "23:59"

    cur = zone.now.strftime("%H:%M")
    if s <= e
      cur >= s && cur < e
    else
      cur >= s || cur < e
    end
  end

  # Enabled with zero days selected reads "Enabled" while never active. The ERB warning and
  # quiet_hours_warning_controller.js both render from this one definition.
  def quiet_hours_deceptive?
    qh = @data["quiet_hours"] || {}
    return false unless qh["enabled"] == true

    days = qh["active_days"]
    days.is_a?(Array) && days.empty?
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

  # Fixed since v2 folded digest controls into email frequency (notifications.md).
  def digest_hour_local
    8
  end

  def retention_days
    return NEVER_CAP_DAYS if @data.key?("retention_days") && @data["retention_days"].nil?

    @data.fetch("retention_days", DEFAULT_RETENTION_DAYS)
  end

  # Next digest send time (8am local) in the user's own timezone.
  def next_due_at
    zone = user_time_zone
    now = Time.current.in_time_zone(zone)
    next_local = zone.local(now.year, now.month, now.day, digest_hour_local)
    next_local += 1.day if next_local <= now
    next_local += 6.days if digest_cadence == "weekly"
    next_local
  end

  def to_h = @data.deep_dup

  # A new object with `changes` validated, coerced and deep-merged; the receiver is untouched,
  # so an InvalidChange raised mid-way leaves no half-applied state.
  def merge(changes)
    return self if changes.blank?

    prepared = changes.deep_stringify_keys.deep_dup
    validate_and_coerce!(prepared)

    self.class.new(@data.deep_dup.deep_merge!(prepared), user: @user)
  end

  # Drives the controller's recompute_digest_due_at decision.
  def digest_changed_by?(changes)
    changes&.dig("delivery_methods", "email", "frequency").present? ||
      changes&.dig(:delivery_methods, :email, :frequency).present?
  end

  private

  # true, false, or :digest. Internal: the public surface is the deliver_now?/defer_to_digest?
  # pair, so no caller compares against the sentinel.
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

  # UserPreferences#time_zone owns the name→zone fallback; this covers the no-user case.
  def user_time_zone
    @user&.preferences&.time_zone || Time.zone
  end

  def quiet_day?(active_days, zone)
    return true unless active_days.is_a?(Array)

    active_days.include?(zone.now.strftime("%A").downcase)
  end

  def recognized?(category, channel)
    CATEGORIES.include?(category) && CHANNELS.include?(channel)
  end

  # Security bypasses type toggles, digest deferral, and quiet hours.
  def security_floor?(category)
    category == SECURITY_CATEGORY
  end

  # In-app security is always on; a user who disabled email entirely accepts that
  # security alerts will not email.
  def security_delivery_allowed?(channel)
    channel != "email" || @data.dig("delivery_methods", "email", "enabled") != false
  end

  def type_enabled?(category)
    @data.dig("notification_types", category) == true
  end

  def channel_enabled?(channel)
    @data.dig("delivery_methods", channel, "enabled") == true
  end

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
        # Rails' hidden-empty sentinel rides along so the day picker posts an array even with
        # no boxes checked; stripped, an empty list means zero days.
        days = days.reject(&:blank?)
        raise InvalidChange unless (days - DAYS_OF_WEEK).empty?
        qh["active_days"] = days
      end
    end

    coerce_booleans!(changes)
  end

  def valid_retention?(value)
    ALLOWED_RETENTION_DAYS.include?(value.to_i)
  end

  def normalize_retention(value)
    value.to_i
  end

  # The form posts strings; the column wants booleans.
  def coerce_booleans!(hash)
    hash.each do |key, value|
      case value
      when "true"  then hash[key] = true
      when "false" then hash[key] = false
      when Hash    then coerce_booleans!(value)
      end
    end
  end
end
