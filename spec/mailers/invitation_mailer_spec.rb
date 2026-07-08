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

    it "includes the workspace name" do
      mail = described_class.invite(invitation)
      expect(mail.body.encoded).to include(invitation.invitable.name)
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

    it "has a subject including workspace name" do
      mail = described_class.invite(invitation)
      expect(mail.subject).to include(invitation.invitable.name)
    end

    it "includes the inviter name in the body" do
      mail = described_class.invite(invitation)
      expect(mail.body.encoded).to include(invitation.invited_by.full_name)
    end

    it "includes the decline link" do
      mail = described_class.invite(invitation)
      expect(mail.body.encoded).to include("decline")
    end
  end
end
