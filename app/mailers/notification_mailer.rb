class NotificationMailer < ApplicationMailer
  # Mailer methods invoked by Noticed via `deliver_by :email, mailer: ..., method: ...`.
  # Noticed dispatches through ActionMailer's parameterized API:
  #   NotificationMailer.with(notification:, record:, recipient:, **event_params).workspace_role_changed
  # so each method reads from `params[:notification]` / `params[:record]` / `params[:recipient]`
  # rather than taking positional arguments. See Noticed::DeliveryMethods::Email for the exact
  # call shape.
  #
  # Convention: the locale subject lives at notification_mailer.<method>.subject
  # with any positional substitutions documented in the per-method signature.

  def workspace_role_changed
    @notification = params[:notification]
    @recipient = params[:recipient]
    @membership = params[:record]
    @workspace = @membership.workspace
    @role = @membership.role

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_role_changed.subject",
                 workspace: @workspace.name)
    )
  end

  def workspace_invitation_expiring_soon
    @notification = params[:notification]
    @recipient = params[:recipient]
    @invitation = params[:record]
    @workspace = @invitation.resolved_workspace
    @hours_remaining = @invitation.expires_in_hours
    @accept_url = accept_invitation_url(token: @invitation.token)

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_invitation_expiring_soon.subject",
                 workspace: @workspace.name)
    )
  end

  def workspace_member_added
    @notification = params[:notification]
    @recipient = params[:recipient]
    @membership = params[:record]
    @workspace = @membership.workspace
    @role = @membership.role

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_member_added.subject",
                 workspace: @workspace.name)
    )
  end

  # Billing alert: a workspace has crossed the 80%-of-capacity threshold for a
  # given metric. notification.params carries `:metric`, `:current`, `:limit`
  # from WorkspaceCapacityApproachingNotifier.with(...).
  #
  # Per-recipient throttle (EmailRecipientThrottle): even though billing is not
  # a security category, capacity alerts for a busy workspace can dispatch to
  # multiple owners simultaneously. The throttle caps repeated sends to a
  # single recipient (e.g., an owner who owns many workspaces, all of which
  # cross the threshold on the same sweep run). Fail-open on cache miss so a
  # cache outage doesn't suppress legitimate alerts.
  def workspace_capacity_approaching
    @notification = params[:notification]
    @recipient = params[:recipient]
    @workspace = params[:record]
    @metric = @notification&.params&.dig(:metric) || @notification&.params&.dig("metric")
    @current = @notification&.params&.dig(:current) || @notification&.params&.dig("current")
    @limit = @notification&.params&.dig(:limit) || @notification&.params&.dig("limit")
    @settings_url = edit_workspace_settings_url(@workspace)

    return unless EmailRecipientThrottle.allow!(@recipient.email_address, kind: :workspace_capacity_approaching)

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.workspace_capacity_approaching.subject",
                 workspace: @workspace.name,
                 metric: @metric)
    )
  end

  # Security alert: a sign-in arrived from a (user_agent, os) digest we haven't
  # seen for this user. The notification.params hash carries `:user_agent` and
  # `:os` from SignInFromNewDeviceNotifier.with(...).
  #
  # Per-recipient throttle (EmailRecipientThrottle): mirrors the pattern in
  # OmniauthCallbacksController#handle_existing_auth — even security-category
  # mail is gated by per-recipient flood protection so a coordinated attack
  # can't flood a single inbox by triggering many novel-device sign-ins. The
  # throttle is checked here (inside the mailer method) rather than at the
  # Notifier callsite because Noticed dispatches via deliver_later through its
  # own job pipeline, not directly through deliver_later from a controller.
  # The throttle fails open if Rails.cache.increment is unavailable, so a
  # cache outage doesn't suppress security alerts.
  def sign_in_from_new_device
    @notification = params[:notification]
    @recipient = params[:recipient]
    @user = params[:record]
    @os = @notification&.params&.dig(:os) || @notification&.params&.dig("os")
    @user_agent = @notification&.params&.dig(:user_agent) || @notification&.params&.dig("user_agent")
    @account_url = account_connected_accounts_url

    return unless EmailRecipientThrottle.allow!(@recipient.email_address, kind: :sign_in_from_new_device)

    mail(
      to: @recipient.email_address,
      subject: t("notification_mailer.sign_in_from_new_device.subject", os: @os)
    )
  end

  # Daily/weekly digest. Unlike the per-event mailers above, `digest` takes
  # positional args (user + array of notifications) because it's invoked
  # directly by `DigestMailerJob`, not through Noticed's `deliver_by :email`
  # parameterized pipeline. Subject reflects the user's chosen cadence;
  # template lays out notifications grouped by category. Task 23 fleshes
  # out the HTML/text templates.
  def digest(user, notifications)
    @user = user
    @notifications = notifications
    @cadence = user.preferences&.notification_preferences_object&.digest_cadence || "daily"
    @app_name = t("application.name", default: "ModelRails")
    @count = notifications.size
    @preferences_url = edit_account_notification_preferences_url

    mail(
      to: user.email_address,
      subject: t("notification_mailer.digest.subject.#{@cadence}", app_name: @app_name)
    )
  end
end
