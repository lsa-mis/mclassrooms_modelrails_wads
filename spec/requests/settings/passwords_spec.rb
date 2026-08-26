require "rails_helper"

RSpec.describe "Account Passwords", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /account/password/new to sign in" do
      get new_settings_password_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    # Factory default: user has a password (password_digest present).
    let(:user) { create(:user) }
    # User with no password set (passwordless — signs in via magic link).
    let(:passwordless_user) { create(:user, password: nil) }

    # #722: the third instance of the forgot-the-layout-opt-in class — the
    # password pages are settings destinations and render inside the shell
    # like every sibling (the sessions page was the second instance, #723).
    describe "settings shell (#722)" do
      before { sign_in(passwordless_user) }

      it "renders the password page inside the settings shell" do
        get new_settings_password_path
        aside = Nokogiri::HTML(response.body).at_css(
          %(aside[aria-label="#{I18n.t("settings.sidebar.aria_label")}"])
        )
        expect(aside).not_to be_nil
      end
    end

    describe "GET /account/password/new" do
      context "user without a password" do
        before { sign_in(passwordless_user) }

        it "renders the add password form" do
          get new_settings_password_path
          expect(response).to have_http_status(:ok)
        end
      end

      context "user with an existing password (already has password)" do
        before { sign_in(user) }

        it "redirects to the change-password form" do
          get new_settings_password_path
          expect(response).to redirect_to(edit_settings_password_path)
        end
      end
    end

    describe "POST /account/password" do
      context "user without a password" do
        before { sign_in(passwordless_user) }

        it "creates email authentication and updates password" do
          expect {
            post settings_password_path, params: {
              user: {
                password: "NewSecureP@ss123!",
                password_confirmation: "NewSecureP@ss123!"
              }
            }
          }.to change(passwordless_user.authentications.email, :count).by(1)
        end

        it "returns unprocessable entity for short password" do
          post settings_password_path, params: {
            user: { password: "short", password_confirmation: "short" }
          }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "user already has a password" do
        before { sign_in(user) }

        it "redirects to the change-password form" do
          post settings_password_path, params: {
            user: {
              password: "NewSecureP@ss123!",
              password_confirmation: "NewSecureP@ss123!"
            }
          }
          expect(response).to redirect_to(edit_settings_password_path)
        end
      end
    end

    describe "PATCH /settings/password (change)" do
      before { sign_in(user) }

      it "updates the password for a user who already has one" do
        patch settings_password_path, params: { user: { password: "brand-new-passw0rd", password_confirmation: "brand-new-passw0rd" } }
        expect(user.reload.authenticate("brand-new-passw0rd")).to be_truthy
      end

      # Revocation now rides inside update_password_with_precheck's transaction,
      # so a rejected password must leave the digest and every other session
      # untouched — no half-applied rotation.
      it "leaves the digest and other sessions intact when the change is rejected" do
        other = user.sessions.create!(user_agent: "other", ip_address: "10.0.0.1")

        patch settings_password_path, params: { user: { password: "short", password_confirmation: "short" } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(Session.exists?(other.id)).to be(true)
        expect(user.reload.authenticate("SecureP@ssw0rd123!")).to be_truthy
      end

      # #674: the HIBP range check is network I/O. Run from the validation it
      # sits inside BEGIN IMMEDIATE — SQLite's database-wide write lock — so a
      # slow third party stalls every write in the app. The controller must
      # precheck before save; depth is measured against the transactional-
      # fixture baseline (one transaction is always open in specs).
      it "runs the HIBP range check outside the write transaction, exactly once" do
        baseline = ActiveRecord::Base.connection.open_transactions
        depth_at_check = nil
        pwned = instance_double(Pwned::Password)
        allow(pwned).to receive(:pwned?) do
          depth_at_check = ActiveRecord::Base.connection.open_transactions
          false
        end
        allow(Pwned::Password).to receive(:new).and_return(pwned)

        patch settings_password_path, params: { user: { password: "brand-new-passw0rd", password_confirmation: "brand-new-passw0rd" } }

        expect(response).to redirect_to(settings_connected_accounts_path)
        expect(pwned).to have_received(:pwned?).once
        expect(depth_at_check).to eq(baseline)
      end
    end

    describe "DELETE /settings/password (remove)" do
      before { sign_in(user) }

      it "removes the password and the email authentication, returning to passwordless" do
        delete settings_password_path
        expect(user.reload.has_password?).to be(false)
      end

      it "fires the removal notification and audit row (was silently skipped via update_columns)" do
        expect {
          delete settings_password_path
        }.to change { ActivityLog.where(action: "user.password_removed", trackable: user).count }.by(1)
          .and change { user.notifications.count }.by(1)
      end

      it "revokes other sessions on removal" do
        other = user.sessions.create!(user_agent: "other", ip_address: "10.0.0.1")
        delete settings_password_path
        expect(Session.exists?(other.id)).to be(false)
        expect(user.reload.password_digest).to be_nil
      end

      # Strict tier: the audit row commits with the credential write or neither
      # does. The rollback has to take the auth teardown with it — that is what
      # proves one transaction wraps the whole unit, not just the digest write.
      it "rolls back the removal atomically when the audit write fails" do
        # Ruling R7 (see spec/models/user_spec.rb): read the digest and build
        # the authentication BEFORE installing the stub, or setup runs under it
        # and the example passes for the wrong reason.
        original_digest = user.password_digest
        auth = user.authentications.create!(
          provider: "email", uid: user.email_address, verified_at: Time.current
        )
        allow(ActivityLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")

        expect { delete settings_password_path }.to raise_error(ActiveRecord::StatementInvalid)

        expect(user.reload.password_digest).to eq(original_digest)
        expect(Authentication.exists?(auth.id)).to be(true)
      end
    end

    describe "GET /settings/password/new for a user who already has a password" do
      before { sign_in(user) }

      it "routes them to the change form instead of add" do
        get new_settings_password_path
        expect(response).to redirect_to(edit_settings_password_path)
      end
    end
  end
end
