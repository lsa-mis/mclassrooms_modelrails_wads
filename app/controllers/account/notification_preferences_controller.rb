# frozen_string_literal: true

module Account
  class NotificationPreferencesController < ApplicationController
    ALLOWED_RETENTION_DAYS = [ 30, 60, 90, 180, 365 ].freeze
    HH_MM_REGEX = /\A([01]\d|2[0-3]):([0-5]\d)\z/

    before_action :set_preferences

    def edit
    end

    def update
      new_prefs = @preferences.notification_preferences.deep_dup

      if (rejected = apply_changes!(new_prefs))
        head :unprocessable_entity
        return
      end

      ActiveRecord::Base.transaction do
        @preferences.update!(notification_preferences: new_prefs)
        recompute_digest_due_at! if digest_changed?
      end

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_account_notification_preferences_path, notice: t(".success") }
      end
    end

    private

    def set_preferences
      @preferences = Current.user.preferences || Current.user.create_preferences!
    end

    # Returns truthy when something failed validation; the caller responds 422.
    # Mutates `target` in place via deep_merge!. Every validation runs BEFORE
    # the merge so a single bad key leaves the entire JSONB untouched —
    # callers don't see half-applied changes.
    def apply_changes!(target)
      raw = params[:notification_preferences]
      return nil if raw.blank?

      changes = raw.to_unsafe_h.deep_stringify_keys

      if changes.key?("retention_days")
        return :rejected unless valid_retention?(changes["retention_days"])
        changes["retention_days"] = normalize_retention(changes["retention_days"])
      end

      if changes.key?("notification_types")
        unknown = changes["notification_types"].keys - NotificationPreferences::CATEGORIES
        return :rejected if unknown.any?
      end

      if (freq = changes.dig("delivery_methods", "email", "frequency"))
        return :rejected unless NotificationPreferences::EMAIL_FREQUENCIES.include?(freq)
      end

      if changes.key?("quiet_hours")
        qh = changes["quiet_hours"]
        return :rejected if qh["start"].present? && !qh["start"].match?(HH_MM_REGEX)
        return :rejected if qh["end"].present?   && !qh["end"].match?(HH_MM_REGEX)
      end

      coerce_booleans!(changes)
      target.deep_merge!(changes)
      nil
    end

    # Blank / "never" => valid (means "never auto-delete").
    # Otherwise the integer form must appear in ALLOWED_RETENTION_DAYS.
    def valid_retention?(value)
      return true if value.blank? || value.to_s == "never"
      ALLOWED_RETENTION_DAYS.include?(value.to_i)
    end

    # Coerce an already-validated retention value to its stored form:
    # nil for "never auto-delete", Integer for a day count.
    def normalize_retention(value)
      return nil if value.blank? || value.to_s == "never"
      value.to_i
    end

    # Recursively coerce "true"/"false" strings to actual booleans so the
    # JSONB column doesn't get string values for boolean toggles.
    def coerce_booleans!(hash)
      hash.each do |key, value|
        case value
        when "true"  then hash[key] = true
        when "false" then hash[key] = false
        when Hash    then coerce_booleans!(value)
        else
          # Coerce digest.hour_local to integer if it's a numeric string.
          hash[key] = value.to_i if key == "hour_local" && value.is_a?(String) && value.match?(/\A\d+\z/)
        end
      end
    end

    def digest_changed?
      # v2: digest scheduling is driven by delivery_methods.email.frequency.
      # When the user changes frequency, recompute next_due_at so the next
      # cycle reflects the new cadence.
      params.dig(:notification_preferences, :delivery_methods, :email, :frequency).present?
    end

    def recompute_digest_due_at!
      tz_name = @preferences.timezone.presence
      timezone = (tz_name && ActiveSupport::TimeZone[tz_name]) || Time.zone
      next_due = @preferences.notification_preferences_object.next_due_at_in(timezone)
      @preferences.update!(digest_next_due_at: next_due)
    end
  end
end
