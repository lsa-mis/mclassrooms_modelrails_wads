require "rails_helper"

RSpec.describe "Email verifications", type: :request do
  describe "GET /email_verification/new" do
    let(:user) { create(:user, :with_email_auth) }

    it "renders the check-your-email screen for a signed-in user" do
      sign_in(user)
      get new_email_verification_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.email_address)
    end

    it "requires authentication" do
      get new_email_verification_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /email_verification_resend" do
    let(:user) { create(:user, :with_email_auth) }

    it "re-enqueues the verification email and returns to the check screen" do
      sign_in(user)
      expect {
        post email_verification_resend_path
      }.to have_enqueued_mail(AuthenticationMailer, :verification_email)
      expect(response).to redirect_to(new_email_verification_path)
    end
  end

  let(:user) { create(:user) }
  let(:authentication) { create(:authentication, user: user) }

  describe "GET /email_verification" do
    context "with valid token" do
      it "verifies the email" do
        get email_verification_path(token: authentication.generate_token_for(:email_verification))
        expect(authentication.reload.verified_at).to be_present
      end

      it "redirects with success message" do
        get email_verification_path(token: authentication.generate_token_for(:email_verification))
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq(I18n.t("email_verifications.show.success"))
      end
    end

    context "with expired token" do
      it "rejects the verification" do
        token = authentication.generate_token_for(:email_verification)
        travel(Authentication::TOKEN_LIFETIME + 1.minute) do
          get email_verification_path(token: token)
        end
        expect(authentication.reload.verified_at).to be_nil
      end
    end

    context "with invalid token" do
      it "rejects the verification" do
        get email_verification_path(token: "invalid")
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end
  end
end
