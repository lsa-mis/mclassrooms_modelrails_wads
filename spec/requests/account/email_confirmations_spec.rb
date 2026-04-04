require "rails_helper"

RSpec.describe "Account Email Confirmations", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  describe "GET /account/email_confirmation" do
    context "with valid token" do
      before do
        user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
        user.reload
      end

      it "updates the email address" do
        get account_email_confirmation_path(token: user.pending_email_token)
        expect(user.reload.email_address).to eq("new@example.com")
      end

      it "redirects with success notice" do
        get account_email_confirmation_path(token: user.pending_email_token)
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "clears pending email" do
        get account_email_confirmation_path(token: user.pending_email_token)
        user.reload
        expect(user.pending_email).to be_nil
        expect(user.pending_email_token).to be_nil
      end
    end

    context "with expired token" do
      before do
        user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
        user.update!(pending_email_sent_at: 25.hours.ago)
        user.reload
      end

      it "rejects and redirects with alert" do
        get account_email_confirmation_path(token: user.pending_email_token)
        expect(response).to redirect_to(edit_account_profile_path)
        expect(user.reload.email_address).not_to eq("new@example.com")
      end
    end

    context "with invalid token" do
      it "rejects and redirects with alert" do
        get account_email_confirmation_path(token: "invalid-token")
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end

    context "with no token" do
      it "rejects and redirects" do
        get account_email_confirmation_path
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end
  end

  describe "DELETE /account/email_confirmation" do
    before do
      user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
    end

    it "clears pending email" do
      delete account_email_confirmation_path
      expect(user.reload.pending_email).to be_nil
    end

    it "redirects with notice" do
      delete account_email_confirmation_path
      expect(response).to redirect_to(edit_account_profile_path)
    end
  end
end
