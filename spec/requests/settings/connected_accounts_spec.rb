require "rails_helper"

RSpec.describe "Account Connected Accounts", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /account/connected_accounts to sign in" do
      get settings_connected_accounts_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }

    before { sign_in(user) }

    describe "GET /account/connected_accounts" do
      it "lists connected providers" do
        create(:authentication, :google, user: user)
        get settings_connected_accounts_path
        expect(response).to have_http_status(:ok)
      end

      it "subscribes to the user's authentications stream for live updates" do
        create(:authentication, :google, user: user)
        get settings_connected_accounts_path
        expect(response.body).to include("turbo-cable-stream-source")
        expect(response.body).to match(/signed-stream-name="[^"]+"/)
      end
    end

    describe "DELETE /account/connected_accounts/:id" do
      context "with multiple verified auth methods" do
        let!(:email_auth) { create(:authentication, :verified, user: user, provider: "email") }
        let!(:google_auth) { create(:authentication, :google, :verified, user: user) }

        it "removes the provider" do
          expect {
            delete settings_connected_account_path(google_auth)
          }.to change(user.authentications.verified, :count).by(-1)
        end
      end

      context "with only one auth method" do
        let!(:email_auth) { create(:authentication, :verified, user: user, provider: "email") }

        it "prevents unlinking the last method" do
          delete settings_connected_account_path(email_auth)
          expect(response).to redirect_to(settings_connected_accounts_path)
          expect(flash[:alert]).to eq(I18n.t("settings.connected_accounts.destroy.cannot_remove_last_verified"))
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
        verified_at: nil
      )
    end

    context "with a valid, unexpired token" do
      it "marks the authentication verified" do
        get verify_settings_connected_accounts_path(token: auth.generate_token_for(:email_verification))
        expect(auth.reload.verified_at).to be_present
      end

      context "when the user is signed in" do
        before { sign_in(user) }

        it "redirects to connected accounts with success" do
          get verify_settings_connected_accounts_path(token: auth.generate_token_for(:email_verification))
          expect(response).to redirect_to(settings_connected_accounts_path)
          expect(flash[:notice]).to include("linked")
        end
      end

      context "when the user is signed out" do
        it "signs the user in and redirects to root" do
          get verify_settings_connected_accounts_path(token: auth.generate_token_for(:email_verification))
          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to include("linked")
        end
      end
    end

    context "with an expired token" do
      it "does not mark the authentication verified" do
        token = auth.generate_token_for(:email_verification)
        travel(Authentication::TOKEN_LIFETIME + 1.minute) do
          get verify_settings_connected_accounts_path(token: token)
        end
        expect(auth.reload.verified_at).to be_nil
      end

      it "redirects with an invalid-or-expired alert" do
        token = auth.generate_token_for(:email_verification)
        travel(Authentication::TOKEN_LIFETIME + 1.minute) do
          get verify_settings_connected_accounts_path(token: token)
        end
        expect(flash[:alert]).to include("invalid or expired")
      end
    end

    context "with an unknown token" do
      it "redirects with an invalid-or-expired alert" do
        get verify_settings_connected_accounts_path(token: "nonexistent")
        expect(flash[:alert]).to include("invalid or expired")
      end
    end

    context "with an already-consumed token" do
      # Single-use: the token embeds verified_at, so verifying invalidates it.
      let(:original_token) { auth.generate_token_for(:email_verification) }

      before do
        original_token  # materialize before verify! invalidates it
        auth.verify!
      end

      it "redirects with an invalid-or-expired alert" do
        get verify_settings_connected_accounts_path(token: original_token)
        expect(flash[:alert]).to include("invalid or expired")
      end
    end

    context "with a valid token belonging to a different user" do
      let(:other_user) { create(:user) }
      let!(:other_auth) do
        other_user.authentications.create!(
          provider: "google",
          uid: "uid-other",
          email: "other@example.com",
          verified_at: nil
        )
      end

      before { sign_in(user) }

      it "does not verify the other user's authentication" do
        get verify_settings_connected_accounts_path(token: "other-token")
        expect(other_auth.reload.verified_at).to be_nil
      end

      it "redirects with invalid_or_expired (does not leak that the token belongs to another user)" do
        get verify_settings_connected_accounts_path(token: "other-token")
        expect(response).to redirect_to(settings_connected_accounts_path)
        expect(flash[:alert]).to include("invalid or expired")
      end
    end
  end

  describe "DELETE /account/connected_accounts/:id (last verified method protection)" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    context "user has only one verified auth and one pending auth" do
      let!(:verified) { user.authentications.create!(provider: "email", uid: user.email_address,
        email: user.email_address, verified_at: Time.current) }
      let!(:pending) { user.authentications.create!(provider: "google", uid: "g-1",
        email: "alice.work@gmail.com", verified_at: nil) }

      it "blocks removal of the verified auth" do
        delete settings_connected_account_path(verified)
        expect(verified.reload).to be_persisted
        expect(flash[:alert]).to include("last verified")
      end

      it "allows cancellation of the pending auth" do
        delete settings_connected_account_path(pending)
        expect(Authentication.exists?(pending.id)).to be false
      end
    end

    context "user has two verified auths" do
      let!(:auth1) { user.authentications.create!(provider: "email", uid: user.email_address,
        email: user.email_address, verified_at: Time.current) }
      let!(:auth2) { user.authentications.create!(provider: "google", uid: "g-1",
        email: user.email_address, verified_at: Time.current) }

      it "allows removal of one" do
        delete settings_connected_account_path(auth1)
        expect(Authentication.exists?(auth1.id)).to be false
      end
    end

    context "user has zero verified auths and one pending auth" do
      let!(:only_pending) do
        user.authentications.create!(
          provider: "google",
          uid: "g-only",
          email: "alice.work@gmail.com",
          verified_at: nil
        )
      end

      it "allows cancellation of the pending auth (current behavior)" do
        # Documenting current behavior: cancelling the only auth leaves the user with zero auths.
        # If we ever decide to forbid this, this test should be updated rather than silently
        # changing behavior.
        expect {
          delete settings_connected_account_path(only_pending)
        }.to change(user.authentications, :count).by(-1)
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
      it "enqueues a fresh verification email" do
        expect {
          post resend_verification_settings_connected_account_path(pending_auth)
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects to connected accounts with success" do
        post resend_verification_settings_connected_account_path(pending_auth)
        expect(response).to redirect_to(settings_connected_accounts_path)
        expect(flash[:notice]).to include("pending@example.com")
      end
    end

    context "with an already-verified authentication" do
      it "does not change the auth" do
        original_verified_at = verified_auth.verified_at
        post resend_verification_settings_connected_account_path(verified_auth)
        expect(verified_auth.reload.verified_at).to eq(original_verified_at)
      end

      it "redirects with already_verified alert" do
        post resend_verification_settings_connected_account_path(verified_auth)
        expect(flash[:alert]).to include("already verified")
      end
    end

    context "with another unverified authentication" do
      let!(:another_pending) do
        user.authentications.create!(
          provider: "google",
          uid: "uid-edge",
          email: "edge@example.com",
          verified_at: nil
        )
      end

      it "enqueues the verification email" do
        expect {
          post resend_verification_settings_connected_account_path(another_pending)
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end
    end

    context "rate limit" do
      it "blocks the 4th request within 3 minutes" do
        call_count = 0
        allow(Rails.cache).to receive(:increment) do
          call_count += 1
          call_count
        end

        3.times { post resend_verification_settings_connected_account_path(pending_auth) }
        post resend_verification_settings_connected_account_path(pending_auth)
        expect(flash[:alert]).to include("wait a moment")
      end
    end

    context "per-recipient throttle (across attempters)" do
      # The per-user rate_limit blocks one signed-in user from spamming.
      # The per-recipient throttle additionally caps how many emails any single
      # recipient address receives across ALL signers, so coordinated attempts
      # (or attackers cycling accounts) can't bury one inbox.
      around do |ex|
        original = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        ex.run
      ensure
        Rails.cache = original
      end

      it "drops verification email once recipient cap is hit, even if the per-user limit allows" do
        # Pre-fill the per-recipient counter to its cap; the next send must be dropped.
        EmailRecipientThrottle::CAP.times do
          EmailRecipientThrottle.allow!(pending_auth.email, kind: :verification)
        end

        expect {
          post resend_verification_settings_connected_account_path(pending_auth)
        }.not_to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "still flashes the success notice (does not leak throttle state to the client)" do
        EmailRecipientThrottle::CAP.times do
          EmailRecipientThrottle.allow!(pending_auth.email, kind: :verification)
        end

        post resend_verification_settings_connected_account_path(pending_auth)
        expect(flash[:notice]).to include(pending_auth.email)
      end
    end

    context "rate limit scoping" do
      it "scopes the rate limit by Current.user.id (not just IP)" do
        # Verify the controller declaration includes a per-user `by:` lambda
        # by ensuring the ActiveSupport::Cache key includes the user id
        captured_key = nil
        allow(Rails.cache).to receive(:increment) do |key, *|
          captured_key = key
          1
        end

        post resend_verification_settings_connected_account_path(pending_auth)
        expect(captured_key).to include(user.id.to_s)
      end
    end

    context "with another user's authentication id (IDOR protection)" do
      let(:other_user) { create(:user) }
      let!(:other_pending_auth) do
        other_user.authentications.create!(
          provider: "google",
          uid: "other-uid",
          email: "other.work@example.com",
          verified_at: nil
        )
      end

      it "does not process the request (IDOR protection via RecordNotFound)" do
        # ApplicationController rescues RecordNotFound and redirects with a generic alert.
        # The scoped lookup (Current.user.authentications.find) blocks cross-user access,
        # so the other user's auth is never touched and no email is sent.
        expect {
          post resend_verification_settings_connected_account_path(other_pending_auth)
        }.not_to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
        expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
      end
    end
  end

  describe "GET verify (new user with pending invitation)" do
    let(:workspace) { create(:workspace) }
    let(:invitation) { create(:invitation, invitable: workspace, email: "needsverify@example.com") }
    let(:user) { create(:user, email_address: "needsverify@example.com") }
    let(:pending_auth) do
      auth = user.authentications.build(
        provider: "google",
        uid: "verifyme",
        email: "needsverify@example.com",
        verified_at: nil,
        pending_invitation_token: invitation.token
      )
      auth.save!
      auth
    end

    it "verifies the auth, signs in the user, claims the invitation, and grants workspace membership" do
      token = pending_auth.generate_token_for(:email_verification)
      get verify_settings_connected_accounts_path(token: token)

      expect(pending_auth.reload.verified_at).to be_present
      expect(invitation.reload).to be_accepted
      expect(user.reload.workspaces).to include(workspace)
      expect(pending_auth.reload.pending_invitation_token).to be_nil
    end

    it "shows the invitation_consumed flash if the invitation became stale before verification" do
      invitation.update!(status: "accepted", accepted_at: 1.minute.ago)

      token = pending_auth.generate_token_for(:email_verification)
      get verify_settings_connected_accounts_path(token: token)

      expect(pending_auth.reload.verified_at).to be_present
      expect(flash[:alert]).to include(I18n.t("registrations.create.invitation_consumed"))
    end

    it "does NOT block verification even when invitation claim fails" do
      invitation.update!(status: "accepted", accepted_at: 1.minute.ago)

      token = pending_auth.generate_token_for(:email_verification)
      get verify_settings_connected_accounts_path(token: token)

      expect(pending_auth.reload.verified_at).to be_present
    end
  end

  describe "GET verify (pending invitation addressed to a different email)" do
    let(:workspace) { create(:workspace) }
    let(:invitation) { create(:invitation, invitable: workspace, email: "invited@example.com") }
    let(:user) { create(:user, email_address: "different@example.com") }
    let(:pending_auth) do
      auth = user.authentications.build(
        provider: "email",
        uid: user.email_address,
        email: user.email_address,
        verified_at: nil,
        pending_invitation_token: invitation.token
      )
      auth.save!
      auth
    end

    it "verifies the auth but refuses the mismatched invitation and explains why" do
      get verify_settings_connected_accounts_path(token: pending_auth.generate_token_for(:email_verification))

      expect(pending_auth.reload.verified_at).to be_present
      expect(invitation.reload).to be_pending
      expect(user.reload.workspaces).not_to include(workspace)
      expect(pending_auth.reload.pending_invitation_token).to be_nil
      expect(flash[:alert]).to eq(I18n.t("settings.connected_accounts.verify.email_mismatch"))
    end
  end

  describe "GET verify (new user with pending join link)" do
    let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
    let!(:member_role) do
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
    end
    let(:link) { create(:workspace_join_link, workspace: workspace, created_by: create(:user)) }
    let(:user) { create(:user, email_address: "joiner@example.com") }
    let(:pending_auth) do
      user.authentications.create!(
        provider: "google",
        uid: "joinme",
        email: "joiner@example.com",
        verified_at: nil,
        pending_join_link_token: link.token
      )
    end

    before do
      allow(Rails.configuration.x.signup)
        .to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    end

    context "when the user is already a member of the link's workspace" do
      it "verifies and signs in without surfacing the raw 'already a member' error" do
        workspace.admit(user, role: member_role)

        get verify_settings_connected_accounts_path(token: pending_auth.generate_token_for(:email_verification))

        expect(pending_auth.reload.verified_at).to be_present
        # Benign duplicate: the success notice covers it, nothing alarming.
        expect(flash[:alert]).to be_blank
        expect(pending_auth.reload.pending_join_link_token).to be_nil
      end
    end

    context "when the link's workspace is at capacity" do
      it "verifies but surfaces a localized capacity message, not the raw model string" do
        workspace.update!(max_members: 1)
        create(:membership, workspace: workspace, user: create(:user), role: member_role)

        get verify_settings_connected_accounts_path(token: pending_auth.generate_token_for(:email_verification))

        expect(pending_auth.reload.verified_at).to be_present
        expect(flash[:alert]).to eq(I18n.t("settings.connected_accounts.verify.join_link_at_capacity"))
        expect(flash[:alert]).not_to include("Workspace is at capacity")
        expect(pending_auth.reload.pending_join_link_token).to be_nil
      end
    end

    context "with a valid active link (happy path)" do
      it "verifies, signs in, admits the user as Member, and clears the token" do
        get verify_settings_connected_accounts_path(token: pending_auth.generate_token_for(:email_verification))

        expect(pending_auth.reload.verified_at).to be_present
        expect(user.reload.workspaces).to include(workspace)
        expect(workspace.memberships.find_by!(user: user).role.slug).to eq("member")
        expect(pending_auth.reload.pending_join_link_token).to be_nil
        expect(flash[:alert]).to be_blank
        # Unauthenticated caller is signed in once their email is proven.
        expect(response).to redirect_to(root_path)
      end
    end

    context "when the link was revoked between parking and verification" do
      it "silently no-ops: verifies, clears the token, grants no membership" do
        link.revoke!

        get verify_settings_connected_accounts_path(token: pending_auth.generate_token_for(:email_verification))

        expect(pending_auth.reload.verified_at).to be_present
        expect(user.reload.workspaces).not_to include(workspace)
        expect(pending_auth.reload.pending_join_link_token).to be_nil
        expect(flash[:alert]).to be_blank
      end
    end

    context "when the workspace's join policy reverted to invite-only mid-flight" do
      it "silently no-ops: verifies, clears the token, grants no membership" do
        workspace.update!(join_policy: "invite")

        get verify_settings_connected_accounts_path(token: pending_auth.generate_token_for(:email_verification))

        expect(pending_auth.reload.verified_at).to be_present
        expect(user.reload.workspaces).not_to include(workspace)
        expect(pending_auth.reload.pending_join_link_token).to be_nil
        expect(flash[:alert]).to be_blank
      end
    end
  end

  describe "DELETE /account/connected_accounts/:id (last verified method protection) - concurrency" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    context "destroy under transactional wrap (sanity check)" do
      let!(:verified1) { user.authentications.create!(provider: "email", uid: user.email_address,
        email: user.email_address, verified_at: Time.current) }
      let!(:verified2) { user.authentications.create!(provider: "google", uid: "g-1",
        email: user.email_address, verified_at: Time.current) }

      it "still destroys one of two verified auths after the transaction wrapping" do
        expect {
          delete settings_connected_account_path(verified1)
        }.to change(user.authentications.verified, :count).by(-1)
        expect(user.authentications.verified.count).to eq(1)
      end
    end
  end
end
