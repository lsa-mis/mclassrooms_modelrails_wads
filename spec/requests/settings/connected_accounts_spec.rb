require "rails_helper"

RSpec.describe "Account Connected Accounts", type: :request do
  def signed_in_user
    user = create(:user, :no_authentications)
    sign_in(user)
    user
  end

  def pending_google_auth(user, uid: "uid-1", email: "alice.work@gmail.com")
    user.authentications.create!(provider: "google", uid: uid, email: email, verified_at: nil)
  end

  describe "unauthenticated access" do
    it "redirects GET /account/connected_accounts to sign in" do
      get settings_connected_accounts_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    describe "GET /account/connected_accounts" do
      it "lists connected providers" do
        user = signed_in_user
        create(:authentication, :google, user: user)
        get settings_connected_accounts_path
        expect(response).to have_http_status(:ok)
      end

      it "subscribes to the user's authentications stream for live updates" do
        user = signed_in_user
        create(:authentication, :google, user: user)
        get settings_connected_accounts_path
        expect(response.body).to include("turbo-cable-stream-source")
        expect(response.body).to match(/signed-stream-name="[^"]+"/)
      end

      it "renders the verified pill through UI::Badge (canonical padding)" do
        user = signed_in_user
        create(:authentication, :verified, user: user, provider: "email")

        get settings_connected_accounts_path

        html = Capybara.string(response.body)
        expect(html).to have_css("span[data-variant='soft'][data-tone='success']",
          exact_text: I18n.t("settings.connected_accounts.index.verified"))
      end
    end

    describe "GET /account/connected_accounts (connecting a provider)" do
      before do
        allow(Rails.application.credentials).to receive(:dig).and_call_original
        allow(Rails.application.credentials).to receive(:dig)
          .with(:oauth, :google, :client_id).and_return("test-google-client-id")
        allow(Rails.application.credentials).to receive(:dig)
          .with(:oauth, :github, :client_id).and_return("test-github-client-id")
      end

      def signed_in_user_with_email_auth
        user = signed_in_user
        create(:authentication, :verified, user: user, provider: "email")
        user
      end

      def connect_buttons
        Capybara.string(response.body).all("form[data-turbo='false'] button.btn-secondary").map(&:text).map(&:strip)
      end

      it "offers a Connect button, posting to the provider, for each enabled provider not yet linked" do
        signed_in_user_with_email_auth

        get settings_connected_accounts_path

        expect(connect_buttons).to contain_exactly(
          I18n.t("settings.connected_accounts.index.connect_action", provider: "Google"),
          I18n.t("settings.connected_accounts.index.connect_action", provider: "GitHub")
        )
        expect(Capybara.string(response.body)).to have_css("form[action='/auth/google_oauth2'][method='post']")
      end

      it "leaves out a provider that is already linked, or waiting on verification" do
        user = signed_in_user_with_email_auth
        create(:authentication, :google, user: user)
        create(:authentication, :github, user: user, verified_at: nil, email: "other@example.com")

        get settings_connected_accounts_path

        expect(connect_buttons).to be_empty
        expect(response.body).not_to include(I18n.t("settings.connected_accounts.index.connect_heading"))
      end
    end

    describe "GET /account/connected_accounts (verified banner)" do
      it "shows an in-document success alert naming the address after verification" do
        user = signed_in_user
        auth = pending_google_auth(user, uid: "uid-banner", email: "banner@example.com")

        # The verification POST redirects here with flash[:verified_email] set;
        # follow_redirect! exercises the flash hand-off end-to-end.
        post settings_connected_account_verification_path,
          params: { token: auth.generate_token_for(:email_verification) }
        follow_redirect!

        banner_text = I18n.t("settings.connected_accounts.index.verified_banner", email: "banner@example.com")
        expect(response.body).to include(banner_text)
        html = Capybara.string(response.body)
        expect(html).to have_css("[role='status']", text: banner_text)
      end
    end

    describe "GET /account/connected_accounts (email label reflects password)" do
      it "labels the email method 'Email and password' when the user has a password" do
        with_pw = create(:user)
        sign_in(with_pw)

        get settings_connected_accounts_path
        expect(response.body).to include(I18n.t("settings.connected_accounts.index.email_provider"))
      end

      it "does not claim 'and password' for a passwordless account" do
        passwordless = create(:user, password: nil)
        sign_in(passwordless)

        get settings_connected_accounts_path
        expect(response.body).not_to include(I18n.t("settings.connected_accounts.index.email_provider"))
        expect(response.body).to include(I18n.t("settings.connected_accounts.index.email_provider_passwordless"))
      end
    end

    describe "GET /account/connected_accounts (unlink offered only when removable)" do
      it "omits the Unlink control when it is the only verified method" do
        user = signed_in_user
        create(:authentication, :verified, user: user, provider: "email")

        get settings_connected_accounts_path
        page = Capybara::Node::Simple.new(response.body)
        expect(page).to have_no_button(I18n.t("settings.connected_accounts.index.disconnect"))
        expect(response.body).to include(I18n.t("settings.connected_accounts.index.only_method_note"))
      end

      it "offers the Unlink control when more than one verified method remains" do
        user = signed_in_user
        create(:authentication, :verified, user: user, provider: "email")
        create(:authentication, :google, :verified, user: user)

        get settings_connected_accounts_path
        page = Capybara::Node::Simple.new(response.body)
        expect(page).to have_button(I18n.t("settings.connected_accounts.index.disconnect"))
      end

      it "associates the only-method note with its heading for screen readers" do
        user = signed_in_user
        create(:authentication, :verified, user: user, provider: "email")

        get settings_connected_accounts_path
        doc = Nokogiri::HTML(response.body)
        note = doc.at_css("p[id$='-sole']")
        expect(note).to be_present
        expect(doc.at_css("p[aria-describedby='#{note['id']}']")).to be_present
      end
    end

    describe "DELETE /account/connected_accounts/:id" do
      context "with multiple verified auth methods" do
        it "removes the provider" do
          user = signed_in_user
          create(:authentication, :verified, user: user, provider: "email")
          google_auth = create(:authentication, :google, :verified, user: user)

          expect {
            delete settings_connected_account_path(google_auth)
          }.to change(user.authentications.verified, :count).by(-1)

          expect(response).to redirect_to(settings_connected_accounts_path)
          expect(flash[:notice]).to eq(I18n.t("settings.connected_accounts.destroy.success", provider: google_auth.display_provider))
        end
      end

      context "with only one auth method" do
        it "prevents unlinking the last method" do
          user = signed_in_user
          email_auth = create(:authentication, :verified, user: user, provider: "email")

          delete settings_connected_account_path(email_auth)
          expect(response).to redirect_to(settings_connected_accounts_path)
          expect(flash[:alert]).to eq(I18n.t("settings.connected_accounts.destroy.cannot_remove_last_verified"))
          expect(user.authentications.count).to eq(1)
        end
      end
    end
  end

  describe "GET /account/connected_accounts/verify (confirmation only)" do
    it "renders the confirmation and verifies nothing" do
      auth = pending_google_auth(create(:user, :no_authentications))

      get settings_connected_account_verification_path(token: auth.generate_token_for(:email_verification))
      expect(response).to have_http_status(:ok)
      expect(auth.reload.verified_at).to be_nil
    end

    it "redirects with an invalid-or-expired alert for an unknown token" do
      get settings_connected_account_verification_path(token: "nonexistent")
      expect(flash[:alert]).to eq(I18n.t("settings.connected_account_verifications.show.invalid_or_expired"))
    end

    it "no longer serves the retired path-token route (#950)" do
      auth = pending_google_auth(create(:user, :no_authentications))

      get "#{settings_connected_account_verification_path}/#{auth.generate_token_for(:email_verification)}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /account/connected_accounts/verify" do
    context "with a valid, unexpired token" do
      it "marks the authentication verified" do
        auth = pending_google_auth(create(:user, :no_authentications))

        post settings_connected_account_verification_path, params: { token: auth.generate_token_for(:email_verification) }
        expect(auth.reload.verified_at).to be_present
      end

      context "when the user is signed in" do
        it "redirects to connected accounts with success and the in-document banner flash" do
          auth = pending_google_auth(signed_in_user)

          post settings_connected_account_verification_path, params: { token: auth.generate_token_for(:email_verification) }
          expect(response).to redirect_to(settings_connected_accounts_path)
          expect(flash[:notice]).to eq(I18n.t("settings.connected_account_verifications.create.success", provider: auth.display_provider))
          expect(flash[:verified_email]).to eq(auth.email)
        end
      end

      context "when the user is signed out" do
        it "signs the user in and lands on the connected-accounts index (outcome is in-document, #950)" do
          auth = pending_google_auth(create(:user, :no_authentications))

          post settings_connected_account_verification_path, params: { token: auth.generate_token_for(:email_verification) }
          expect(response).to redirect_to(settings_connected_accounts_path)
          expect(flash[:notice]).to eq(I18n.t("settings.connected_account_verifications.create.success", provider: auth.display_provider))
          expect(flash[:verified_email]).to eq(auth.email)
        end
      end
    end

    # Refused before verify!, so the token survives the hold (#1129).
    context "when the account is suspended" do
      def suspended_user
        user = create(:user, :no_authentications)
        user.update!(suspended_at: Time.current)
        user
      end

      it "refuses before spending the token or verifying the authentication" do
        auth = pending_google_auth(suspended_user)
        token = auth.generate_token_for(:email_verification)

        post settings_connected_account_verification_path, params: { token: token }

        expect(auth.reload.verified_at).to be_nil,
          "the authentication was verified for a suspended user, and the parked claim orphaned"
      end

      # The intermediate state, or the first post's verification passes this.
      it "leaves the token usable once the hold lifts" do
        user = suspended_user
        auth = pending_google_auth(user)
        token = auth.generate_token_for(:email_verification)
        post settings_connected_account_verification_path, params: { token: token }
        expect(auth.reload.verified_at).to be_nil

        user.update!(suspended_at: nil)
        post settings_connected_account_verification_path, params: { token: token }

        expect(auth.reload.verified_at).to be_present,
          "the first attempt spent the token, so the user cannot finish after the hold lifts"
      end
    end

    context "with an expired token" do
      it "does not mark the authentication verified" do
        auth = pending_google_auth(create(:user, :no_authentications))
        token = auth.generate_token_for(:email_verification)
        travel(Authentication::TOKEN_LIFETIME + 1.minute) do
          post settings_connected_account_verification_path, params: { token: token }
        end
        expect(auth.reload.verified_at).to be_nil
      end

      it "redirects with an invalid-or-expired alert" do
        auth = pending_google_auth(create(:user, :no_authentications))
        token = auth.generate_token_for(:email_verification)
        travel(Authentication::TOKEN_LIFETIME + 1.minute) do
          post settings_connected_account_verification_path, params: { token: token }
        end
        expect(flash[:alert]).to eq(I18n.t("settings.connected_account_verifications.show.invalid_or_expired"))
      end
    end

    context "with an unknown token" do
      it "redirects with an invalid-or-expired alert" do
        post settings_connected_account_verification_path, params: { token: "nonexistent" }
        expect(flash[:alert]).to eq(I18n.t("settings.connected_account_verifications.show.invalid_or_expired"))
      end
    end

    context "with an already-consumed token" do
      it "redirects with an invalid-or-expired alert" do
        auth = pending_google_auth(create(:user, :no_authentications))
        # Single-use: the token embeds verified_at, so verifying invalidates it.
        original_token = auth.generate_token_for(:email_verification)
        auth.verify!

        post settings_connected_account_verification_path, params: { token: original_token }
        expect(flash[:alert]).to eq(I18n.t("settings.connected_account_verifications.show.invalid_or_expired"))
      end
    end

    context "with a valid token belonging to a different user" do
      def other_users_pending_auth
        pending_google_auth(create(:user, :no_authentications), uid: "uid-other", email: "other@example.com")
      end

      it "does not verify the other user's authentication" do
        other_auth = other_users_pending_auth
        signed_in_user

        post settings_connected_account_verification_path, params: { token: "other-token" }
        expect(other_auth.reload.verified_at).to be_nil
      end

      it "redirects with invalid_or_expired (does not leak that the token belongs to another user)" do
        other_users_pending_auth
        signed_in_user

        post settings_connected_account_verification_path, params: { token: "other-token" }
        expect(response).to redirect_to(settings_connected_accounts_path)
        expect(flash[:alert]).to eq(I18n.t("settings.connected_account_verifications.show.invalid_or_expired"))
      end
    end
  end

  describe "DELETE /account/connected_accounts/:id (last verified method protection)" do
    def verified_email_auth(user)
      user.authentications.create!(provider: "email", email: user.email_address, verified_at: Time.current)
    end

    context "user has only one verified auth and one pending auth" do
      it "blocks removal of the verified auth" do
        user = signed_in_user
        verified = verified_email_auth(user)
        pending_google_auth(user, uid: "g-1")

        delete settings_connected_account_path(verified)
        expect(verified.reload).to be_persisted
        expect(flash[:alert]).to eq(I18n.t("settings.connected_accounts.destroy.cannot_remove_last_verified"))
      end

      it "allows cancellation of the pending auth" do
        user = signed_in_user
        verified_email_auth(user)
        pending = pending_google_auth(user, uid: "g-1")

        delete settings_connected_account_path(pending)
        expect(Authentication.exists?(pending.id)).to be false
      end
    end

    context "user has two verified auths" do
      it "allows removal of one" do
        user = signed_in_user
        auth1 = verified_email_auth(user)
        user.authentications.create!(provider: "google", uid: "g-1", email: user.email_address, verified_at: Time.current)

        delete settings_connected_account_path(auth1)
        expect(Authentication.exists?(auth1.id)).to be false
      end
    end

    context "user has zero verified auths and one pending auth" do
      it "allows cancellation of the pending auth (current behavior)" do
        user = signed_in_user
        only_pending = pending_google_auth(user, uid: "g-only")

        # Pins current behavior: cancelling the only auth leaves zero auths.
        # Forbidding that later means changing this test deliberately.
        expect {
          delete settings_connected_account_path(only_pending)
        }.to change(user.authentications, :count).by(-1)
      end
    end
  end

  # Resending the verification email is the create of a verification resend nested under the account (#1007).
  describe "POST /account/connected_accounts/:id/verification_resend" do
    def resendable_auth(user)
      pending_google_auth(user, uid: "uid-2", email: "pending@example.com")
    end

    context "with a pending authentication" do
      it "enqueues a fresh verification email" do
        pending_auth = resendable_auth(signed_in_user)

        expect {
          post settings_connected_account_verification_resend_path(pending_auth)
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects to connected accounts with success" do
        pending_auth = resendable_auth(signed_in_user)

        post settings_connected_account_verification_resend_path(pending_auth)
        expect(response).to redirect_to(settings_connected_accounts_path)
        expect(flash[:notice]).to eq(I18n.t("settings.connected_accounts.verification_resends.create.resent", email: "pending@example.com"))
      end
    end

    context "with an already-verified authentication" do
      def verified_github_auth(user)
        user.authentications.create!(provider: "github", uid: "uid-3", email: "verified@example.com", verified_at: Time.current)
      end

      it "does not change the auth" do
        verified_auth = verified_github_auth(signed_in_user)

        original_verified_at = verified_auth.verified_at
        post settings_connected_account_verification_resend_path(verified_auth)
        expect(verified_auth.reload.verified_at).to eq(original_verified_at)
      end

      it "redirects with already_verified alert" do
        verified_auth = verified_github_auth(signed_in_user)

        post settings_connected_account_verification_resend_path(verified_auth)
        expect(flash[:alert]).to eq(I18n.t("settings.connected_accounts.verification_resends.create.already_verified"))
      end
    end

    context "with another unverified authentication" do
      it "enqueues the verification email" do
        another_pending = pending_google_auth(signed_in_user, uid: "uid-edge", email: "edge@example.com")

        expect {
          post settings_connected_account_verification_resend_path(another_pending)
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end
    end

    context "rate limit" do
      it "blocks the 4th request within 3 minutes" do
        user = signed_in_user
        call_count = 0
        allow(Rails.cache).to receive(:increment) do
          call_count += 1
          call_count
        end
        pending_auth = resendable_auth(user)

        3.times { post settings_connected_account_verification_resend_path(pending_auth) }
        post settings_connected_account_verification_resend_path(pending_auth)
        expect(flash[:alert]).to eq(I18n.t("settings.connected_accounts.verification_resends.create.rate_limited"))
      end
    end

    context "per-recipient throttle (across attempters)" do
      # The per-user rate_limit stops one user spamming; the per-recipient throttle caps
      # what one address receives across ALL signers, so cycling accounts can't bury an inbox.
      around do |ex|
        original = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        ex.run
      ensure
        Rails.cache = original
      end

      it "drops verification email once recipient cap is hit, even if the per-user limit allows" do
        pending_auth = resendable_auth(signed_in_user)
        # Pre-fill the per-recipient counter to its cap; the next send must be dropped.
        EmailRecipientThrottle::CAP.times do
          EmailRecipientThrottle.allow!(pending_auth.email, kind: :verification)
        end

        expect {
          post settings_connected_account_verification_resend_path(pending_auth)
        }.not_to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "still flashes the success notice (does not leak throttle state to the client)" do
        pending_auth = resendable_auth(signed_in_user)
        EmailRecipientThrottle::CAP.times do
          EmailRecipientThrottle.allow!(pending_auth.email, kind: :verification)
        end

        post settings_connected_account_verification_resend_path(pending_auth)
        expect(flash[:notice]).to eq(I18n.t("settings.connected_accounts.verification_resends.create.resent", email: pending_auth.email))
      end
    end

    context "rate limit scoping" do
      it "scopes the rate limit by Current.user.id (not just IP)" do
        user = signed_in_user
        # Verify the controller declaration includes a per-user `by:` lambda
        # by ensuring the ActiveSupport::Cache key includes the user id
        captured_key = nil
        allow(Rails.cache).to receive(:increment) do |key, *|
          captured_key = key
          1
        end

        post settings_connected_account_verification_resend_path(resendable_auth(user))
        expect(captured_key).to include(user.id.to_s)
      end
    end

    context "with another user's authentication id (IDOR protection)" do
      it "does not process the request (IDOR protection via RecordNotFound)" do
        signed_in_user
        other_pending_auth = pending_google_auth(create(:user, :no_authentications),
          uid: "other-uid", email: "other.work@example.com")

        # The scoped lookup (Current.user.authentications.find) raises RecordNotFound, which
        # ApplicationController turns into a generic alert: no touch, no email.
        expect {
          post settings_connected_account_verification_resend_path(other_pending_auth)
        }.not_to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
        expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
      end
    end
  end

  describe "POST verify (new user with pending invitation)" do
    def needsverify_user
      create(:user, :no_authentications, email_address: "needsverify@example.com")
    end

    def needsverify_invitation(workspace)
      create(:invitation, invitable: workspace, email: "needsverify@example.com")
    end

    def parked_invitation_auth(user, invitation)
      user.authentications.create!(
        provider: "google",
        uid: "verifyme",
        email: "needsverify@example.com",
        verified_at: nil,
        pending_invitation_token: invitation.token
      )
    end

    it "verifies the auth, signs in the user, claims the invitation, and grants workspace membership" do
      user = needsverify_user
      workspace = create(:workspace)
      invitation = needsverify_invitation(workspace)
      pending_auth = parked_invitation_auth(user, invitation)

      token = pending_auth.generate_token_for(:email_verification)
      post settings_connected_account_verification_path, params: { token: token }

      expect(pending_auth.reload.verified_at).to be_present
      expect(invitation.reload).to be_accepted
      expect(user.reload.workspaces).to include(workspace)
      expect(pending_auth.reload.pending_invitation_token).to be_nil
    end

    it "shows the invitation_consumed flash if the invitation became stale before verification" do
      invitation = needsverify_invitation(create(:workspace))
      invitation.update!(status: "accepted", accepted_at: 1.minute.ago)
      pending_auth = parked_invitation_auth(needsverify_user, invitation)

      token = pending_auth.generate_token_for(:email_verification)
      post settings_connected_account_verification_path, params: { token: token }

      expect(pending_auth.reload.verified_at).to be_present
      expect(flash[:alert]).to include(I18n.t("registrations.create.invitation_consumed"))
    end

    it "does NOT block verification even when invitation claim fails" do
      invitation = needsverify_invitation(create(:workspace))
      invitation.update!(status: "accepted", accepted_at: 1.minute.ago)
      pending_auth = parked_invitation_auth(needsverify_user, invitation)

      token = pending_auth.generate_token_for(:email_verification)
      post settings_connected_account_verification_path, params: { token: token }

      expect(pending_auth.reload.verified_at).to be_present
    end
  end

  describe "POST verify (pending invitation addressed to a different email)" do
    it "verifies the auth but refuses the mismatched invitation and explains why" do
      user = create(:user, :no_authentications, email_address: "different@example.com")
      workspace = create(:workspace)
      invitation = create(:invitation, invitable: workspace, email: "invited@example.com")
      pending_auth = user.authentications.create!(
        provider: "email",
        email: user.email_address,
        verified_at: nil,
        pending_invitation_token: invitation.token
      )

      post settings_connected_account_verification_path, params: { token: pending_auth.generate_token_for(:email_verification) }

      expect(pending_auth.reload.verified_at).to be_present
      expect(invitation.reload).to be_pending
      expect(user.reload.workspaces).not_to include(workspace)
      expect(pending_auth.reload.pending_invitation_token).to be_nil
      expect(flash[:alert]).to eq(I18n.t("settings.connected_accounts.verify.email_mismatch"))
    end
  end

  describe "POST verify (new user with pending join link)" do
    def ensure_member_role
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
    end

    def join_link_for(workspace)
      create(:workspace_join_link, workspace: workspace, created_by: create(:user))
    end

    def joiner
      create(:user, :no_authentications, email_address: "joiner@example.com")
    end

    def parked_join_auth(user, link)
      user.authentications.create!(
        provider: "google",
        uid: "joinme",
        email: "joiner@example.com",
        verified_at: nil,
        pending_join_link_digest: WorkspaceJoinLink.digest(link.plaintext_token)
      )
    end

    before { permit_open_join_links }

    context "when the user is already a member of the link's workspace" do
      it "verifies and signs in without surfacing the raw 'already a member' error" do
        member_role = ensure_member_role
        workspace = create(:workspace, :open_link)
        user = joiner
        workspace.admit(user, role: member_role)
        pending_auth = parked_join_auth(user, join_link_for(workspace))

        post settings_connected_account_verification_path, params: { token: pending_auth.generate_token_for(:email_verification) }

        expect(pending_auth.reload.verified_at).to be_present
        # Benign duplicate: the success notice covers it, nothing alarming.
        expect(flash[:alert]).to be_blank
        expect(pending_auth.reload.pending_join_link_digest).to be_nil
      end
    end

    context "when the link's workspace is at capacity" do
      it "verifies but surfaces a localized capacity message, not the raw model string" do
        member_role = ensure_member_role
        workspace = create(:workspace, :open_link)
        workspace.update!(max_members: 1)
        create(:membership, workspace: workspace, user: create(:user), role: member_role)
        pending_auth = parked_join_auth(joiner, join_link_for(workspace))

        post settings_connected_account_verification_path, params: { token: pending_auth.generate_token_for(:email_verification) }

        expect(pending_auth.reload.verified_at).to be_present
        expect(flash[:alert]).to eq(I18n.t("settings.connected_accounts.verify.join_link_at_capacity"))
        expect(flash[:alert]).not_to include("Workspace is at capacity")
        expect(pending_auth.reload.pending_join_link_digest).to be_nil
      end
    end

    context "with a valid active link (happy path)" do
      it "verifies, signs in, admits the user as Member, and clears the token" do
        ensure_member_role
        user = joiner
        workspace = create(:workspace, :open_link)
        pending_auth = parked_join_auth(user, join_link_for(workspace))

        post settings_connected_account_verification_path, params: { token: pending_auth.generate_token_for(:email_verification) }

        expect(pending_auth.reload.verified_at).to be_present
        expect(user.reload.workspaces).to include(workspace)
        expect(workspace.memberships.find_by!(user: user).role.slug).to eq("member")
        expect(pending_auth.reload.pending_join_link_digest).to be_nil
        expect(flash[:alert]).to be_blank
        # Unauthenticated caller is signed in once their email is proven; the
        # outcome is shown in-document on the connected-accounts index (#950).
        expect(response).to redirect_to(settings_connected_accounts_path)
      end
    end

    context "when the link was revoked between parking and verification" do
      it "silently no-ops: verifies, clears the token, grants no membership" do
        ensure_member_role
        workspace = create(:workspace, :open_link)
        link = join_link_for(workspace)
        link.revoke!
        user = joiner
        pending_auth = parked_join_auth(user, link)

        post settings_connected_account_verification_path, params: { token: pending_auth.generate_token_for(:email_verification) }

        expect(pending_auth.reload.verified_at).to be_present
        expect(user.reload.workspaces).not_to include(workspace)
        expect(pending_auth.reload.pending_join_link_digest).to be_nil
        expect(flash[:alert]).to be_blank
      end
    end

    # Privacy (T14d): at this claim site a suspended workspace must look exactly like a
    # revoked link; the visitor was never a member, so nothing about the lock may leak.
    context "when the workspace was suspended between parking and verification" do
      it "silently no-ops: verifies, clears the token, grants no membership" do
        ensure_member_role
        workspace = create(:workspace, :open_link)
        workspace.suspend!
        user = joiner
        pending_auth = parked_join_auth(user, join_link_for(workspace))

        post settings_connected_account_verification_path, params: { token: pending_auth.generate_token_for(:email_verification) }

        expect(pending_auth.reload.verified_at).to be_present
        expect(user.reload.workspaces).not_to include(workspace)
        expect(pending_auth.reload.pending_join_link_digest).to be_nil
        expect(flash[:alert]).to be_blank
        expect(flash[:alert]).not_to eq(I18n.t("workspaces.locked_notice"))
      end
    end

    # T5: archived and deleted workspaces look like a revoked link here too; the widened
    # admittable? guard covers all three non-active states at this claim site.
    %i[archive discard].each do |lifecycle_action|
      lifecycle_name = lifecycle_action == :archive ? "archived" : "deleted"

      context "when the workspace was #{lifecycle_name} between parking and verification" do
        it "silently no-ops: verifies, clears the token, grants no membership" do
          ensure_member_role
          workspace = create(:workspace, :open_link)
          workspace.public_send("#{lifecycle_action}!")
          user = joiner
          pending_auth = parked_join_auth(user, join_link_for(workspace))

          post settings_connected_account_verification_path, params: { token: pending_auth.generate_token_for(:email_verification) }

          expect(pending_auth.reload.verified_at).to be_present
          expect(user.reload.workspaces).not_to include(workspace)
          expect(pending_auth.reload.pending_join_link_digest).to be_nil
          expect(flash[:alert]).to be_blank
          expect(flash[:alert]).not_to match(/archived|deleted|locked|suspended/i)
        end
      end
    end

    context "when the workspace's join policy reverted to invite-only mid-flight" do
      it "silently no-ops: verifies, clears the token, grants no membership" do
        ensure_member_role
        workspace = create(:workspace, :open_link)
        workspace.update!(join_policy: "invite")
        user = joiner
        pending_auth = parked_join_auth(user, join_link_for(workspace))

        post settings_connected_account_verification_path, params: { token: pending_auth.generate_token_for(:email_verification) }

        expect(pending_auth.reload.verified_at).to be_present
        expect(user.reload.workspaces).not_to include(workspace)
        expect(pending_auth.reload.pending_join_link_digest).to be_nil
        expect(flash[:alert]).to be_blank
      end
    end
  end

  describe "DELETE /account/connected_accounts/:id (last verified method protection) - concurrency" do
    context "destroy under transactional wrap (sanity check)" do
      it "still destroys one of two verified auths after the transaction wrapping" do
        user = signed_in_user
        verified1 = user.authentications.create!(provider: "email",
          email: user.email_address, verified_at: Time.current)
        user.authentications.create!(provider: "google", uid: "g-1",
          email: user.email_address, verified_at: Time.current)

        expect {
          delete settings_connected_account_path(verified1)
        }.to change(user.authentications.verified, :count).by(-1)
        expect(user.authentications.verified.count).to eq(1)
      end
    end
  end
end
