# frozen_string_literal: true

module Settings
  class NotificationsController < ApplicationController
    before_action :set_notification, only: [ :update, :destroy, :open ]
    before_action :authorize_notification, only: [ :update, :destroy, :open ]

    def index
      authorize Noticed::Notification, :index?, policy_class: NotificationPolicy
      # `event.record` is the polymorphic notifiable each notifier's `#message`
      # interpolates into its locale string. Eager-loaded across all subtypes
      # because the common case interpolates record. SignInFromNewDeviceNotifier
      # is the lone exception (reads only `event.params`); its unused `:record`
      # is safelisted in `config/environments/test.rb` to keep Bullet quiet.
      scope = policy_scope(Noticed::Notification, policy_scope_class: NotificationPolicy::Scope)
                .includes(:recipient, event: :record)
                .order(created_at: :desc)
      scope = scope.where(read_at: nil) if params[:filter] == "unread"
      if params[:category].present?
        scope = scope.where(type: ApplicationNotifier.notification_types_for(params[:category]))
      end
      @current_filter = current_filter_key
      @pagy, @notifications = pagy(scope, limit: 25)
    end

    def update
      @notification.update!(read_at: mark_read? ? Time.current : nil)
      broadcast_bell_refresh
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: settings_notifications_path }
      end
    end

    def destroy
      # Capture read-state before destroy! so we can decide whether other
      # tabs need a bell-button refresh. Destroying an unread notification
      # drops the user's unread count; destroying a read one doesn't change
      # the badge so we skip the broadcast to avoid pointless work.
      was_unread = @notification.read_at.nil?
      @notification.destroy!
      broadcast_bell_refresh if was_unread
      redirect_to settings_notifications_path, notice: t("notifications.destroy.success")
    end

    # GET /account/notifications/:id/open
    # Bell-dropdown click handler: marks the notification as read (idempotent)
    # and redirects to the notifier's `#url`. Each notifier subclass owns its
    # destination via `notification_methods do; def url; ...; end; end`.
    def open
      if @notification.read_at.nil?
        @notification.update!(read_at: Time.current)
        broadcast_bell_refresh
      end
      redirect_to @notification.url
    end

    def mark_all_read
      authorize Noticed::Notification, :mark_all_read?, policy_class: NotificationPolicy
      # Single atomic UPDATE: WHERE clause is evaluated once, rows un-marked
      # concurrently can't slip past a moving cursor (the in_batches race
      # the panel flagged), and every row gets the same timestamp instead
      # of per-batch drift. Per-user volume here is bounded by retention
      # caps — if it ever grows, route the heavy lift to PR-5's sweep job.
      now = Time.current
      Current.user.notifications.where(read_at: nil)
                                .update_all(read_at: now, updated_at: now)
      broadcast_bell_refresh
      redirect_to settings_notifications_path,
                  notice: t("notifications.index.mark_all_read.success")
    end

    def destroy_all_read
      authorize Noticed::Notification, :destroy_all_read?, policy_class: NotificationPolicy
      # delete_all (not destroy_all): Noticed::Notification has no
      # destroy callbacks and no `dependent:` cascades pointing OUT from
      # it (the only cascade is INTO it from noticed_events via the
      # `dependent: :delete_all` on Noticed::Event#has_many :notifications).
      # Single DELETE, no row instantiation, no callback overhead.
      Current.user.notifications.where.not(read_at: nil).delete_all
      redirect_to settings_notifications_path,
                  notice: t("notifications.index.destroy_all_read.success")
    end

    private

    # Cross-tab read-state sync: refresh the current user's notification
    # surfaces (bell-button frame, dropdown-list frame, aria-live region)
    # after any read-state mutation (single mark/unmark, bulk mark-all-read,
    # bell-dropdown open, destroy-when-unread). Tab A's direct HTTP response
    # already refreshes its own surfaces; this broadcast covers Tab B and
    # any other open browser tab/window. The actual three-broadcast trio
    # lives in NotificationBroadcaster so the notifier callback path and
    # this controller path share one implementation.
    def broadcast_bell_refresh
      NotificationBroadcaster.refresh_for(Current.user, announcement_key: "notifications.bell.read_state_announcement")
    end

    def set_notification
      @notification = Current.user.notifications.find(params[:id])
    end

    def authorize_notification
      authorize @notification, policy_class: NotificationPolicy
    end

    # Boolean predicate: was the request asking to mark-as-read (any truthy
    # `read_at` param value) or to unmark? Naming makes the discard explicit
    # — the user-supplied `read_at` value itself is intentionally NOT used
    # as a timestamp; we always stamp `Time.current` server-side.
    def mark_read?
      params[:read_at].present?
    end

    def current_filter_key
      return "unread" if params[:filter] == "unread"
      return params[:category] if params[:category].present?
      "all"
    end
  end
end
