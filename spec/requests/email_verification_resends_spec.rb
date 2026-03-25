require "rails_helper"

RSpec.describe "Email Verification Resends", type: :request do
  let(:user) { create(:user) }
  let!(:authentication) { create(:authentication, user: user, provider: "email", uid: user.email_address) }

  before { sign_in(user) }

  describe "POST /email_verification_resend" do
    it "sends a new verification email" do
      expect {
        post email_verification_resend_path
      }.to have_enqueued_mail(AuthenticationMailer, :verification_email)
    end

    it "generates a fresh token" do
      old_token = authentication.verification_token
      post email_verification_resend_path
      expect(authentication.reload.verification_token).not_to eq(old_token)
    end

    context "already verified" do
      before { authentication.verify! }

      it "redirects with notice" do
        post email_verification_resend_path
        expect(flash[:notice]).to eq(I18n.t("email_verification_resends.create.already_verified"))
      end
    end
  end
end
