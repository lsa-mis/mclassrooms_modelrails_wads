require "rails_helper"

RSpec.describe InvitationMailer, type: :mailer do
  describe "#invite" do
    let(:invitation) { create(:invitation) }

    it "sends to the invitee's email" do
      mail = described_class.with(invitation: invitation).invite
      expect(mail.to).to eq([ invitation.email ])
    end

    it "includes the accept link" do
      mail = described_class.with(invitation: invitation).invite
      expect(mail.body.encoded).to include(invitation.token)
    end

    # D4: the invitee has consented to nothing yet, so the invitation does not
    # disclose the workspace's name. It appears once, on the accept/decline page.
    it "does not disclose the workspace name in the body" do
      mail = described_class.with(invitation: invitation).invite
      expect(mail.body.encoded).not_to include(invitation.invitable.name)
    end
  end


  describe "#invite details" do
    let(:invitation) { create(:invitation) }

    it "names the app rather than the workspace in the subject" do
      mail = described_class.with(invitation: invitation).invite
      expect(mail.subject).not_to include(invitation.invitable.name)
      expect(mail.subject).to include(I18n.t("application.name"))
    end

    # The inviter is identified by their verified address, not a display name
    # they chose — the address is the part the invitee can actually judge.
    it "identifies the inviter by their address in the body" do
      mail = described_class.with(invitation: invitation).invite
      expect(mail.body.encoded).to include(invitation.invited_by.email_address)
    end

    it "includes the decline link" do
      mail = described_class.with(invitation: invitation).invite
      expect(mail.body.encoded).to include("decline")
    end
  end

  describe "deliverability guard" do
    include ActiveJob::TestHelper

    it "delivers nothing to a blocked address and stamps the invitation (T11)" do
      invitation = create(:invitation)
      create(:invitation_block, inviter: invitation.invited_by, email: invitation.email)

      perform_enqueued_jobs do
        described_class.with(invitation: invitation).invite.deliver_later
      end

      expect(ActionMailer::Base.deliveries).to be_empty
      expect(Invitation.find(invitation.id)).to be_suppressed
      expect(ActivityLog.where(action: "invitation.delivery_suppressed",
                               trackable: invitation).count).to eq(1)
    end

    it "still sends to an unblocked address" do
      invitation = create(:invitation)
      perform_enqueued_jobs do
        described_class.with(invitation: invitation).invite.deliver_later
      end
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "does not deliver, stamp, or record for magic links (T12)" do
      invitation = create(:invitation, :magic_link)
      perform_enqueued_jobs do
        described_class.with(invitation: invitation).invite.deliver_later
      end
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(Invitation.find(invitation.id)).not_to be_suppressed
      expect(ActivityLog.where(action: "invitation.delivery_suppressed").count).to eq(0)
    end
  end

  describe "the \"Don't invite me again\" link (#951)" do
    let(:invitation) { create(:invitation) }

    it "puts a signed block-confirmation link in both parts of the invitation mail" do
      mail = described_class.with(invitation: invitation).invite
      html = mail.html_part.body.decoded
      text = mail.text_part.body.decoded

      # The apostrophe is entity-escaped in the HTML part.
      expect(CGI.unescapeHTML(html)).to include(I18n.t("invitation_mailer.invite.block_action"))
      expect(text).to include("#{I18n.t("invitation_mailer.invite.block_action")}: http")
      url = text[%r{https?://\S+/invitation_block\?token=\S+}]
      expect(url).to be_present
      token = Rack::Utils.parse_query(URI.parse(url).query)["token"]
      expect(Invitation.find_by_token_for(:block_confirmation, token)).to eq(invitation)
    end
  end
end
