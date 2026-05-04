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
end
