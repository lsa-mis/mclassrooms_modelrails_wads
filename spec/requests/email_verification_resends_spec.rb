require "rails_helper"

RSpec.describe "Email Verification Resends", type: :request do
  describe "unauthenticated access" do
    it "redirects POST /email_verification_resend to sign in" do
      post email_verification_resend_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user, :unverified_email) }
    let(:authentication) { user.authentications.email.sole }

    before { sign_in(user) }

    describe "POST /email_verification_resend" do
      it "sends a new verification email" do
        expect {
          post email_verification_resend_path
        }.to have_enqueued_mail(AuthenticationMailer, :verification_email)
      end

      describe "POST when user has no email authentication" do
        before do
          user.authentications.destroy_all
        end

        it "redirects with alert" do
          post email_verification_resend_path
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to be_present
        end
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
end
