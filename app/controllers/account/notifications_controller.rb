# frozen_string_literal: true

module Account
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
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: account_notifications_path }
      end
    end

    def destroy
      @notification.destroy!
      redirect_to account_notifications_path, notice: t("notifications.destroy.success")
    end

    # GET /account/notifications/:id/open
    # Bell-dropdown click handler: marks the notification as read (idempotent)
    # and redirects to the notifier's `#url`. Each notifier subclass owns its
    # destination via `notification_methods do; def url; ...; end; end`.
    def open
      @notification.update!(read_at: Time.current) if @notification.read_at.nil?
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
      redirect_to account_notifications_path,
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
      redirect_to account_notifications_path,
                  notice: t("notifications.index.destroy_all_read.success")
    end

    private

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
