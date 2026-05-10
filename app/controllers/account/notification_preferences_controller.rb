# frozen_string_literal: true

module Account
  class NotificationPreferencesController < ApplicationController
    ALLOWED_RETENTION_DAYS = [ 30, 60, 90, 180, 365 ].freeze

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
    # Mutates `target` in place via deep_merge!.
    def apply_changes!(target)
      raw = params[:notification_preferences]
      return nil if raw.blank?

      changes = raw.to_unsafe_h.deep_stringify_keys

      # Retention is the only key with a constrained allowlist; validate
      # before merging so an invalid value never lands in the JSONB.
      if changes.key?("retention_days")
        normalized = normalize_retention(changes["retention_days"])
        return :rejected if normalized == :invalid
        changes["retention_days"] = normalized
      end

      coerce_booleans!(changes)
      target.deep_merge!(changes)
      nil
    end

    # Empty string / "never" => nil ("never auto-delete").
    # Numeric strings allowed only if they're in ALLOWED_RETENTION_DAYS.
    def normalize_retention(value)
      return nil if value.blank? || value.to_s == "never"

      days = value.to_i
      return :invalid unless ALLOWED_RETENTION_DAYS.include?(days)
      days
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
      params.dig(:notification_preferences, :digest).present?
    end

    def recompute_digest_due_at!
      tz_name = @preferences.timezone.presence
      timezone = (tz_name && ActiveSupport::TimeZone[tz_name]) || Time.zone
      next_due = @preferences.notification_preferences_object.next_due_at_in(timezone)
      @preferences.update!(digest_next_due_at: next_due)
    end
  end
end
