require "rails_helper"

RSpec.describe "Magic Link Callbacks", type: :request do
  describe "GET /magic_link_callback/:token" do
    context "valid token for existing user" do
      let(:user) { create(:user) }
      let(:token) { MagicLinkToken.create_for_email(user.email_address) }

      it "signs in the user and redirects to root" do
        get magic_link_callback_path(token: token)
        expect(response).to redirect_to(root_path)
      end

      it "consumes the token" do
        get magic_link_callback_path(token: token)
        token_record = MagicLinkToken.find_by(token: token)
        expect(token_record.consumed_at).to be_present
      end

      it "sets a signed-in notice" do
        get magic_link_callback_path(token: token)
        expect(flash[:notice]).to be_present
      end
    end

    context "valid token for new email (no existing user)" do
      let(:token) { MagicLinkToken.create_for_email("brand-new@example.com") }

      it "renders the registration form" do
        get magic_link_callback_path(token: token)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("magic_link_callbacks.new_registration.title"))
      end

      it "does not consume the token" do
        get magic_link_callback_path(token: token)
        token_record = MagicLinkToken.find_by(token: token)
        expect(token_record.consumed_at).to be_nil
      end
    end

    context "invalid token" do
      it "redirects to sign in with an alert" do
        get magic_link_callback_path(token: "totally-bogus-token")
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "already-consumed token" do
      let(:user) { create(:user) }

      it "redirects to sign in" do
        token = MagicLinkToken.create_for_email(user.email_address)
        MagicLinkToken.find_by(token: token).consume!
        get magic_link_callback_path(token: token)
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "valid token with set_password intent" do
      let(:user) { create(:user) }
      let(:token) { MagicLinkToken.create_for_email(user.email_address, intent: "set_password") }

      it "signs in and lands on the change-password form" do
        get magic_link_callback_path(token: token)
        expect(response).to redirect_to(edit_settings_password_path)
      end
    end

    context "expired token" do
      let(:user) { create(:user) }

      it "redirects to sign in" do
        token = MagicLinkToken.create_for_email(user.email_address)
        MagicLinkToken.find_by(token: token).update!(expires_at: 1.hour.ago)
        get magic_link_callback_path(token: token)
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "POST /magic_link_callback/:token" do
    context "valid token and valid user params" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }
      let(:token) { MagicLinkToken.create_for_email("newreg@example.com") }

      it "creates the user" do
        expect {
          post magic_link_callback_path(token: token), params: {
            user: { first_name: "Jane", last_name: "Doe" }
          }
        }.to change(User, :count).by(1)
      end

      it "creates a verified email authentication" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        user = User.find_by(email_address: "newreg@example.com")
        auth = user.authentications.find_by(provider: "email")
        expect(auth).to be_present
        expect(auth.verified_at).to be_present
      end

      it "consumes the token" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        token_record = MagicLinkToken.find_by(token: token)
        expect(token_record.consumed_at).to be_present
      end

      it "signs in and redirects to root" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        expect(response).to redirect_to(root_path)
      end
    end

    context "valid token but invalid user params" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }
      let(:token) { MagicLinkToken.create_for_email("baddatauser@example.com") }

      it "returns unprocessable entity for blank first_name" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "", last_name: "Doe" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "re-renders the registration form" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "", last_name: "Doe" }
        }
        expect(response.body).to include(I18n.t("magic_link_callbacks.new_registration.title"))
      end

      it "does not consume the token" do
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "", last_name: "Doe" }
        }
        token_record = MagicLinkToken.find_by(token: token)
        expect(token_record.consumed_at).to be_nil
      end
    end

    context "invalid token" do
      it "redirects to sign in" do
        post magic_link_callback_path(token: "garbage"), params: {
          user: { first_name: "Jane", last_name: "Doe" }
        }
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "already-consumed token" do
      it "redirects to sign in" do
        token = MagicLinkToken.create_for_email("consumed-reg@example.com")
        MagicLinkToken.find_by(token: token).consume!
        post magic_link_callback_path(token: token), params: {
          user: { first_name: "Test", last_name: "User" }
        }
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "POST /magic_link_callback/:token (new-user signup)" do
    let(:workspace) { create(:workspace) }
    let(:token_record) { create(:magic_link_token, email: "newml@example.com") }
    let(:params) { { user: { first_name: "Magic", last_name: "Link" } } }

    context "in invite_only mode without an invitation token in session" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

      it "redirects to new_session_path with 303 and creates no User" do
        expect {
          post magic_link_callback_path(token: token_record.token), params: params
        }.not_to change(User, :count)

        expect(response).to redirect_to(new_session_path)
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include(I18n.t("registrations.closed.oauth_blocked"))
      end

      it "does NOT consume the magic-link token" do
        post magic_link_callback_path(token: token_record.token), params: params
        expect(token_record.reload.consumed_at).to be_nil
      end
    end

    context "in invite_only mode with a valid invitation token in session" do
      let(:invitation) { create(:invitation, invitable: workspace, email: "newml@example.com") }

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        # POST to the invitation acceptance route — sets session[:pending_invitation_token]
        post accept_invitation_path(token: invitation.token)
      end

      it "creates the user, consumes the token, accepts the invitation" do
        expect {
          post magic_link_callback_path(token: token_record.token), params: params
        }.to change(User, :count).by(1)

        expect(token_record.reload.consumed_at).to be_present
        expect(invitation.reload).to be_accepted

        new_user = User.find_by(email_address: "newml@example.com")
        expect(new_user.workspaces).to include(workspace)
      end
    end

    context "when the magic-link token gets consumed concurrently (race)" do
      let(:invitation) { create(:invitation, invitable: workspace, email: "newml@example.com") }

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        # POST to the invitation acceptance route — sets session[:pending_invitation_token]
        post accept_invitation_path(token: invitation.token)
        # Simulate concurrent consumption (returns nil to indicate race-lost)
        allow(MagicLinkToken).to receive(:consume!).and_return(nil)
      end

      it "rolls back user creation when token consume returns nil" do
        expect {
          post magic_link_callback_path(token: token_record.token), params: params
        }.not_to change(User, :count)

        expect(invitation.reload).to be_pending
      end
    end

    context "registration via magic link with a pending open-link join token" do
      let(:join_workspace) { create(:workspace, join_policy: :open_link) }
      let(:join_link) { create(:workspace_join_link, workspace: join_workspace) }

      before do
        # Permit :open_link at both the instance level (SignupPolicy) and the
        # workspace level (validates join_policy_must_be_permitted_by_instance).
        allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies)
          .and_return([ :invite, :open_link ])
        # Open-mode signup so the magic-link callback doesn't gate on invite_only.
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
        # default_self_join_role calls Role.find_by!(slug: "member") — ensure it exists.
        Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
        # POST to the join route — sets session[:pending_join_token].
        post workspace_join_path(workspace_slug: join_workspace.slug, token: join_link.token)
      end

      it "admits the brand-new magic-link user as a member" do
        token = MagicLinkToken.create_for_email("joiner@example.com")

        expect {
          post magic_link_callback_path(token: token), params: {
            user: { first_name: "Jo", last_name: "Iner" }
          }
        }.to change(User, :count).by(1)

        user = User.find_by(email_address: "joiner@example.com")
        expect(user.memberships.kept.where(workspace: join_workspace)).to exist
      end

      # Privacy (T14d): no existing spec covers a revoked link at this signup
      # call site (Signupable#accept_pending_join_link!), so this suspended
      # example is added directly alongside the happy path above rather than
      # mirroring a revoked-link sibling. A suspended workspace must behave
      # exactly like a revoked link here: the visitor was never a member, so
      # signup must still succeed with no membership granted and no hint that
      # the workspace is locked.
      context "when the workspace was suspended between parking and signup" do
        before { join_workspace.suspend! }

        it "signs up the user without granting membership or leaking the lock" do
          token = MagicLinkToken.create_for_email("suspended-joiner@example.com")

          expect {
            post magic_link_callback_path(token: token), params: {
              user: { first_name: "Sus", last_name: "Pended" }
            }
          }.to change(User, :count).by(1)

          user = User.find_by(email_address: "suspended-joiner@example.com")
          expect(user.memberships.kept.where(workspace: join_workspace)).not_to exist
          expect(flash[:alert]).not_to eq(I18n.t("workspaces.locked_notice"))
        end
      end
    end

    context "registration via magic link with a pending invitation" do
      let(:inv_workspace) { create(:workspace) }
      let(:invitation) { create(:invitation, invitable: inv_workspace, email: "invitee@example.com") }

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        # POST to the invitation acceptance route — sets session[:pending_invitation_token]
        post accept_invitation_path(token: invitation.token)
      end

      it "accepts the invitation and creates the membership" do
        token = MagicLinkToken.create_for_email("invitee@example.com")

        expect {
          post magic_link_callback_path(token: token), params: {
            user: { first_name: "In", last_name: "Vitee" }
          }
        }.to change(User, :count).by(1)

        user = User.find_by(email_address: "invitee@example.com")
        expect(user.memberships.kept).to exist
      end
    end
  end
end
