class InvitationMailer < ApplicationMailer
  def invite(invitation)
    return if invitation.email.nil?  # Magic links don't send emails

    @invitation = invitation
    @inviter = invitation.invited_by
    @role = invitation.role
    @workspace = invitation.invitable

    @accept_url = accept_invitation_url(token: invitation.token)
    @decline_url = decline_invitation_url(token: invitation.token)

    mail(
      to: invitation.email,
      subject: t("invitation_mailer.invite.subject", workspace: @workspace.name)
    )
  end
end
