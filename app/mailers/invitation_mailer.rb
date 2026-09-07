class InvitationMailer < ApplicationMailer
  before_action :abort_unless_deliverable

  def invite
    invitation = params[:invitation]
    @invitation = invitation
    @inviter = invitation.invited_by
    @role = invitation.role
    @workspace = invitation.invitable

    @accept_url = accept_invitation_url(token: invitation.token)
    @decline_url = decline_invitation_url(token: invitation.token)
    @block_url = invitation_block_url(token: invitation.generate_token_for(:block_confirmation))

    mail(
      to: invitation.email,
      subject: t("invitation_mailer.invite.subject", app_name: t("application.name"))
    )
  end

  private

  # Halting the chain leaves a NullMail — deliver is a no-op; the mechanism the
  # deleted nil-email returns relied on.
  #
  # DEVIATION from spec §8.2's literal `throw :abort`: a `before_action`'s throw
  # is uncaught on Rails 8.1.3.1 (AbstractController's terminator checks
  # `performed?`, it does not `catch(:abort)`), so the halt signal is
  # `response_body` instead — same intent, message never built. The terminator
  # archaeology is in 43ea87f2's commit message.
  def abort_unless_deliverable
    invitation = params[:invitation]
    return if invitation.deliverable?
    # Magic link: nothing to deliver — not a suppression; no stamp, no row.
    invitation.suppress_delivery!(mailer_action: action_name) if invitation.has_invitee?
    self.response_body = ""
  end
end
