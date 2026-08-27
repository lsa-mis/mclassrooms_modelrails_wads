require "rails_helper"

# D13: an invite submission is a fan-out amplifier — one request, N emails to
# addresses the sender chose. The cap bounds that per submission; the
# controller's rate_limit bounds submissions. Both layers, not either.
RSpec.describe "Invitation address-list cap", type: :model do
  let(:cap) { Invitation::MAX_EMAILS_PER_SUBMISSION }

  def address_list(count)
    Array.new(count) { |i| "invitee#{i}@example.test" }.join(", ")
  end

  describe ".parse_email_list" do
    it "returns every address when the submission is within the cap" do
      parsed = Invitation.parse_email_list(address_list(cap))

      expect(parsed.emails.size).to eq(cap)
      expect(parsed).not_to be_over_limit
    end

    it "caps the list and says so when the submission exceeds it" do
      parsed = Invitation.parse_email_list(address_list(cap + 5))

      expect(parsed.emails.size).to eq(cap)
      expect(parsed).to be_over_limit
    end

    it "still parses the mixed comma/newline shape the forms submit" do
      parsed = Invitation.parse_email_list("a@x.test, b@y.test\nc@z.test")

      expect(parsed.emails).to eq([ "a@x.test", "b@y.test", "c@z.test" ])
      expect(parsed).not_to be_over_limit
    end
  end

  describe ".bulk_invite!" do
    let(:workspace) { create(:workspace) }
    let(:inviter) { create(:user) }
    let(:role) { Role.system_default!("member") }

    it "sends no more than the cap and reports the truncation" do
      result = Invitation.bulk_invite!(workspace: workspace, emails: address_list(cap + 3),
                                       role: role, invited_by: inviter)

      expect(result[:sent]).to eq(cap)
      expect(result[:over_limit]).to be(true)
      expect(workspace.invitations.count).to eq(cap)
    end

    it "reports no truncation for a submission within the cap" do
      result = Invitation.bulk_invite!(workspace: workspace, emails: address_list(3),
                                       role: role, invited_by: inviter)

      expect(result[:sent]).to eq(3)
      expect(result[:over_limit]).to be(false)
    end
  end
end
