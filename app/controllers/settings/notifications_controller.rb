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
      # `event.record` is the polymorphic notifiable each notifier's `#message`
      # interpolates into its locale string. Eager-loaded across all subtypes
      # because the common case interpolates record. SignInFromNewDeviceNotifier
      # is the lone exception (reads only `event.params`); its unused `:record`
      # is safelisted in `lib/bullet_safelists.rb` to keep Bullet quiet.
      # Unread first, then newest (D11). Newest-first alone buries an older
      # unread item under newer read ones — and unread is the only state that
      # still needs the reader's attention. `read_at IS NULL` is 1/0 in SQLite,
      # so DESC floats the unread rows.
      #
      # Measured plan, not assumed: SQLite picks
      # index_noticed_notifications_on_recipient (the two-column one) for the
      # recipient filter and then USE TEMP B-TREE FOR ORDER BY — it does not
      # use the four-column recipient_read_created index, and the expression
      # sort is not index-covered. The temp sort spans the recipient's rows,
      # which LIMIT bounds on output but not on input. Fine at per-user
      # notification volumes; revisit if a fork's counts grow.
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
