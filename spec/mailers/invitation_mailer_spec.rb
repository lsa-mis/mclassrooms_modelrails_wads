require "rails_helper"

RSpec.describe InvitationMailer, type: :mailer do
  describe "#invite" do
    let(:invitation) { create(:invitation) }

    it "sends to the invitee's email" do
      mail = described_class.invite(invitation)
      expect(mail.to).to eq([invitation.email])
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
end
