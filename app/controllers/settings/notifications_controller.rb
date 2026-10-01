# frozen_string_literal: true

module Settings
  # Deliberately NOT `layout "settings"` (#722 ruling): the inbox is a
  # full-width triage surface reached from the user-menu bell, not a sidebar
  # destination — the sidebar's "Notifications" item points at notification
  # PREFERENCES, which does carry the shell. Recorded in the
  # settings_layout_opt_in code-smell spec's rulings.
  class NotificationsController < ApplicationController
    before_action :set_notification, only: [ :update ]
    before_action :authorize_notification, only: [ :update ]

    def index
      authorize Noticed::Notification, :index?, policy_class: NotificationPolicy
      # `event.record` is what each notifier's `#message` interpolates; the one notifier
      # that reads only `event.params` has its unused `:record` safelisted in lib/bullet_safelists.rb.

      # Unread first, then newest (D11); `read_at IS NULL` is 1/0 in SQLite, so DESC floats unread.
      # Plan pinned in spec/models/noticed_hardening_spec.rb: composite index seek, temp B-tree sort.
      scope = policy_scope(Noticed::Notification, policy_scope_class: NotificationPolicy::Scope)
                .includes(:recipient, event: :record)
                .order(Arel.sql("noticed_notifications.read_at IS NULL DESC"), created_at: :desc)
      scope = scope.where(read_at: nil) if params[:filter] == "unread"
      if params[:category].present?
        scope = scope.where(type: ApplicationNotifier.notification_types_for(params[:category]))
      end
      @current_filter = current_filter_key
      @retention_days = ApplicationNotifier.preferences_for(Current.user).retention_days
      @pagy, @notifications = pagy(scope, limit: 25)
      # Second stage of the eager load: `includes` stops at the polymorphic
      # record, so each notifier declares what its `#message` traverses
      # (`record_preloads`) and this batch-loads those per subtype.
      ApplicationNotifier.preload_records(@notifications)
    end

    def update
      @notification.update!(read_at: marking_as_read? ? Time.current : nil)
      broadcast_bell_refresh
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: settings_notifications_path }
      end
    end

    private

    # Cross-tab read-state sync: the acting tab's direct HTTP response
    # refreshes its own surfaces; this broadcast covers every other open
    # tab/window. The broadcast targets live in NotificationBroadcaster so
    # the notifier callback path and this controller path share one
    # implementation. See /docs/developer/notifications (Cross-tab read-state sync).
    def broadcast_bell_refresh
      NotificationBroadcaster.refresh_for(Current.user, announcement_key: "notifications.bell.read_state_announcement")
    end

    def set_notification
      @notification = Current.user.notifications.find(params[:id])
    end

    def authorize_notification
      authorize @notification, policy_class: NotificationPolicy
    end

    # The user-supplied `read_at` param is boolean intent only — never trusted
    # as a timestamp; the server always stamps `Time.current`.
    def marking_as_read?
      params[:read_at].present?
    end

    def current_filter_key
      return "unread" if params[:filter] == "unread"
      return params[:category] if params[:category].present?
      "all"
    end
  end
end
