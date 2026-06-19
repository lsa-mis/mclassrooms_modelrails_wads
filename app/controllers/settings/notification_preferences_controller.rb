# frozen_string_literal: true

module Settings
  class NotificationPreferencesController < ApplicationController
    layout "settings"
    settings_context :identity

    before_action :set_preferences

    def edit
      authorize @preferences, policy_class: Settings::NotificationPreferencesPolicy
    end

    def update
      authorize @preferences, policy_class: Settings::NotificationPreferencesPolicy

      raw_changes = preference_changes_param
      new_object = @preferences.notification_preferences_object.merge(raw_changes)

      ActiveRecord::Base.transaction do
        @preferences.update!(notification_preferences: new_object.to_h)
        recompute_digest_due_at! if new_object.digest_changed_by?(raw_changes)
      end

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_settings_notification_preferences_path, notice: t(".success") }
      end
    rescue NotificationPreferences::InvalidChange
      head :unprocessable_entity
    end

    # Idempotent dismiss for the migration-shift banner. First call stamps
    # `dismissed_notifications_redesign_banner_at = Time.current`; subsequent
    # calls are no-ops so the original dismissal time is preserved (matters
    # for any analytics that watch first-dismissal latency).
    def dismiss_banner
      authorize @preferences, policy_class: Settings::NotificationPreferencesPolicy

      if @preferences.dismissed_notifications_redesign_banner_at.nil?
        @preferences.update!(dismissed_notifications_redesign_banner_at: Time.current)
      end

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to edit_settings_notification_preferences_path }
      end
    end

    private

    def set_preferences
      @preferences = Current.user.preferences || Current.user.create_preferences!
    end

    # The notification_preferences form posts a nested hash that's a
    # partial-change patch (only the fields the user modified are present).
    # to_unsafe_h is intentional — every key is shape-validated by
    # NotificationPreferences#merge against CATEGORIES / EMAIL_FREQUENCIES /
    # DAYS_OF_WEEK / ALLOWED_RETENTION_DAYS / HH_MM_REGEX before being
    # deep-merged, so a tampered payload can't introduce arbitrary keys.
    def preference_changes_param
      raw = params[:notification_preferences]
      return {} if raw.blank?
      raw.to_unsafe_h.deep_stringify_keys
    end

    def recompute_digest_due_at!
      tz_name = @preferences.timezone.presence
      timezone = (tz_name && ActiveSupport::TimeZone[tz_name]) || Time.zone
      next_due = @preferences.notification_preferences_object.next_due_at_in(timezone)
      @preferences.update!(digest_next_due_at: next_due)
    end
  end
end
