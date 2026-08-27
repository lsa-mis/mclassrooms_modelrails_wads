require "rails_helper"

RSpec.describe InvitationMailer, type: :mailer do
  describe "#invite" do
    let(:invitation) { create(:invitation) }

    it "sends to the invitee's email" do
      mail = described_class.invite(invitation)
      expect(mail.to).to eq([ invitation.email ])
    end

    it "includes the accept link" do
      mail = described_class.invite(invitation)
      expect(mail.body.encoded).to include(invitation.token)
    end

    # D4: the invitee has consented to nothing yet, so the invitation does not
    # disclose the workspace's name. It appears once, on the accept/decline page.
    it "does not disclose the workspace name in the body" do
      mail = described_class.invite(invitation)
      expect(mail.body.encoded).not_to include(invitation.invitable.name)
    end
  end

  describe "#invite with magic link" do
    let(:invitation) { create(:invitation, :magic_link) }

    it "does not deliver for magic link invitations (no email sent)" do
      expect { described_class.invite(invitation).deliver_now }
        .not_to have_enqueued_mail(InvitationMailer, :invite)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "#invite details" do
    let(:invitation) { create(:invitation) }

    it "names the app rather than the workspace in the subject" do
      mail = described_class.invite(invitation)
      expect(mail.subject).not_to include(invitation.invitable.name)
      expect(mail.subject).to include(I18n.t("application.name"))
    end

    # The inviter is identified by their verified address, not a display name
    # they chose — the address is the part the invitee can actually judge.
    it "identifies the inviter by their address in the body" do
      mail = described_class.invite(invitation)
      expect(mail.body.encoded).to include(invitation.invited_by.email_address)
    end

    it "includes the decline link" do
      mail = described_class.invite(invitation)
      expect(mail.body.encoded).to include("decline")
    end
  end
end
