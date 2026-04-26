require "rails_helper"

RSpec.describe "Account Connected Accounts", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /account/connected_accounts to sign in" do
      get account_connected_accounts_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }

    before { sign_in(user) }

    describe "GET /account/connected_accounts" do
      it "lists connected providers" do
        create(:authentication, :google, user: user)
        get account_connected_accounts_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "DELETE /account/connected_accounts/:id" do
      context "with multiple auth methods" do
        let!(:email_auth) { create(:authentication, user: user, provider: "email") }
        let!(:google_auth) { create(:authentication, :google, user: user) }

        it "removes the provider" do
          expect {
            delete account_connected_account_path(google_auth)
          }.to change(user.authentications, :count).by(-1)
        end
      end

      context "with only one auth method" do
        let!(:email_auth) { create(:authentication, user: user, provider: "email") }

        it "prevents unlinking the last method" do
          delete account_connected_account_path(email_auth)
          expect(response).to redirect_to(account_connected_accounts_path)
          expect(flash[:alert]).to eq(I18n.t("account.connected_accounts.destroy.last_method"))
          expect(user.authentications.count).to eq(1)
        end
      end
    end
  end

  describe "GET /account/connected_accounts/verify/:token" do
    let(:user) { create(:user) }
    let(:auth) do
      user.authentications.create!(
        provider: "google",
        uid: "uid-1",
        email: "alice.work@gmail.com",
        verification_token: "valid-token",
        verification_sent_at: 1.hour.ago,
        verified_at: nil
      )
    end

    context "with a valid, unexpired token" do
      it "marks the authentication verified" do
        get verify_account_connected_accounts_path(token: auth.verification_token)
        expect(auth.reload.verified_at).to be_present
        expect(auth.verification_token).to be_nil
      end

      context "when the user is signed in" do
        before { sign_in(user) }

        it "redirects to connected accounts with success" do
          get verify_account_connected_accounts_path(token: auth.verification_token)
          expect(response).to redirect_to(account_connected_accounts_path)
          expect(flash[:notice]).to include("linked")
        end
      end

      context "when the user is signed out" do
        it "redirects to sign-in with sign-in success message" do
          get verify_account_connected_accounts_path(token: auth.verification_token)
          expect(response).to redirect_to(new_session_path)
          expect(flash[:notice]).to include("Sign in to continue")
        end
      end
    end

    context "with an expired token" do
      before { auth.update!(verification_sent_at: 25.hours.ago) }

      it "does not mark the authentication verified" do
        get verify_account_connected_accounts_path(token: auth.verification_token)
        expect(auth.reload.verified_at).to be_nil
      end

      it "redirects with an invalid-or-expired alert" do
        get verify_account_connected_accounts_path(token: auth.verification_token)
        expect(flash[:alert]).to include("invalid or expired")
      end
    end

    context "with an unknown token" do
      it "redirects with an invalid-or-expired alert" do
        get verify_account_connected_accounts_path(token: "nonexistent")
        expect(flash[:alert]).to include("invalid or expired")
      end
    end

    context "with an already-consumed token" do
      let(:original_token) { auth.verification_token }

      before do
        original_token  # materialize before verify! clears it
        auth.verify!
      end

      it "redirects with an invalid-or-expired alert" do
        get verify_account_connected_accounts_path(token: original_token)
        expect(flash[:alert]).to include("invalid or expired")
      end
    end
  end

  describe "POST /account/connected_accounts/:id/resend_verification" do
    let(:user) { create(:user) }
    let(:pending_auth) do
      user.authentications.create!(
        provider: "google",
        uid: "uid-2",
        email: "pending@example.com",
        verification_token: "old-token",
        verification_sent_at: 1.hour.ago,
        verified_at: nil
      )
    end
    let(:verified_auth) do
      user.authentications.create!(
        provider: "github",
        uid: "uid-3",
        email: "verified@example.com",
        verified_at: Time.current
      )
    end

    before { sign_in(user) }

    context "with a pending authentication" do
      it "regenerates the token" do
        old_token = pending_auth.verification_token
        post resend_verification_account_connected_account_path(pending_auth)
        expect(pending_auth.reload.verification_token).not_to eq(old_token)
      end

      it "enqueues a fresh verification email" do
        expect {
          post resend_verification_account_connected_account_path(pending_auth)
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects to connected accounts with success" do
        post resend_verification_account_connected_account_path(pending_auth)
        expect(response).to redirect_to(account_connected_accounts_path)
        expect(flash[:notice]).to include("pending@example.com")
      end
    end

    context "with an already-verified authentication" do
      it "does not change the auth" do
        original_verified_at = verified_auth.verified_at
        post resend_verification_account_connected_account_path(verified_auth)
        expect(verified_auth.reload.verified_at).to eq(original_verified_at)
      end

      it "redirects with not_pending alert" do
        post resend_verification_account_connected_account_path(verified_auth)
        expect(flash[:alert]).to include("already verified")
      end
    end

    context "rate limit" do
      it "blocks the 4th request within 3 minutes" do
        call_count = 0
        allow(Rails.cache).to receive(:increment) do
          call_count += 1
          call_count
        end

        3.times { post resend_verification_account_connected_account_path(pending_auth) }
        post resend_verification_account_connected_account_path(pending_auth)
        expect(flash[:alert]).to include("wait a moment")
      end
    end
  end
end
