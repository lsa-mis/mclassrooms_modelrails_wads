class InvitationMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @workspace = invitation.invitable
    @inviter = invitation.invited_by
    @role = invitation.role
    @accept_url = accept_invitation_url(token: invitation.token)
    @decline_url = decline_invitation_url(token: invitation.token)

    mail(
      to: invitation.email,
      subject: t("invitation_mailer.invite.subject", workspace: @workspace.name)
    )
  end
end
