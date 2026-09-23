require "rails_helper"

# Signing in with a magic link is the create of a session nested under the
# callback: POST /magic_link_callback/:token/session. Was
# the sign_in member action on MagicLinkCallbacksController (#1007). GET on the callback only
# renders the confirmation (SEC-5); this POST is the state-changing half.
RSpec.describe "Magic Link Callback Sessions", type: :request do
  describe "POST /magic_link_callback/:token/session" do
    let(:user) { create(:user) }

    it "consumes the token and signs the existing user in" do
      token = MagicLinkToken.create_for_email(user.email_address)
      post magic_link_callback_session_path(token)
      expect(MagicLinkToken.find_by(token_digest: MagicLinkToken.digest(token)).consumed_at).to be_present
      expect(response).to redirect_to(root_path)
      get root_path
      expect(response).to have_http_status(:ok) # session established
    end

    it "honors the set_password intent's return path" do
      token = MagicLinkToken.create_for_email(user.email_address, intent: "set_password")
      post magic_link_callback_session_path(token)
      expect(response).to redirect_to(edit_settings_password_path)
    end

    it "rejects an already-consumed token" do
      token = MagicLinkToken.create_for_email(user.email_address)
      MagicLinkToken.consume!(token)
      post magic_link_callback_session_path(token)
      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to be_present
    end

    it "rejects a bogus token" do
      post magic_link_callback_session_path("nope")
      expect(response).to redirect_to(new_session_path)
    end

    it "refuses a suspended user's otherwise-valid link" do
      suspended_user = create(:user, :suspended)
      token = MagicLinkToken.create_for_email(suspended_user.email_address)

      post magic_link_callback_session_path(token)

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("sessions.create.suspended"))
      expect(suspended_user.sessions.count).to eq(0)
    end

    # #846. A second POST of the token that just signed this browser in — a
    # double-click, a browser retry, a Capybara re-dispatch on a loaded shard.
    # The token is spent, so `consume!` returns nil and the old code answered
    # "This magic link is invalid or has expired" on the signed-in homepage:
    # the user IS signed in, and is told the opposite. In CI that surfaced as
    # `sign_in_via_form` failing inside an unrelated spec.
    describe "a replayed sign-in POST" do
      it "tells a signed-in owner they are signed in, not that the link expired" do
        token = MagicLinkToken.create_for_email(user.email_address)
        post magic_link_callback_session_path(token)

        post magic_link_callback_session_path(token)

        expect(response).to redirect_to(root_path) # authenticated_home_path for a non-client-only user
        expect(flash[:alert]).to be_blank
        expect(flash[:notice]).to eq(I18n.t("authentication.already_signed_in"))
      end

      # This used to assert the replay honoured the spent token's intent. It
      # cannot: `consumed_at` is written both by redemption AND by superseding,
      # so a "spent" token may be one the user never clicked (#1083). Routing
      # them to "set your password" because of a link they ignored states
      # something that did not happen.
      #
      # The GET callback has always answered `already_signed_in` and gone to
      # the authenticated home. The POST is the one that disagreed; it now
      # matches. Intent routing is untouched for a REAL redemption — only the
      # replay, where the intent may never have been acted on, drops it.
      it "does not route a replay by the spent token's intent" do
        token = MagicLinkToken.create_for_email(user.email_address, intent: "set_password")
        post magic_link_callback_session_path(token)

        post magic_link_callback_session_path(token)

        expect(response).to redirect_to(root_path) # authenticated_home_path for a non-client-only user
      end

      # A superseded link is the reachable case the moment replay detection
      # reaches the GET: request a link, ignore it, request another, sign in,
      # then click the first email. It was never redeemed, so the answer must
      # not claim it was.
      it "answers the same for a superseded link the user never clicked" do
        superseded = MagicLinkToken.create_for_email(user.email_address, intent: "set_password")
        current = MagicLinkToken.create_for_email(user.email_address)
        post magic_link_callback_session_path(current)

        post magic_link_callback_session_path(superseded)

        expect(response).to redirect_to(root_path) # authenticated_home_path for a non-client-only user
        expect(flash[:notice]).to eq(I18n.t("authentication.already_signed_in"))
      end

      it "starts no second session" do
        token = MagicLinkToken.create_for_email(user.email_address)
        post magic_link_callback_session_path(token)

        expect { post magic_link_callback_session_path(token) }
          .not_to change { user.sessions.count }
      end

      # The fence. Only the address the token belongs to may read a spent
      # token as its own replay — otherwise a signed-in visitor holding
      # somebody else's used link would be told they are that person.
      it "still rejects a spent token belonging to a different address" do
        other = create(:user)
        others_token = MagicLinkToken.create_for_email(other.email_address)
        MagicLinkToken.consume!(others_token)

        post magic_link_callback_session_path(MagicLinkToken.create_for_email(user.email_address))
        post magic_link_callback_session_path(others_token)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("magic_link_callbacks.show.invalid"))
      end
    end
  end

  describe "POST /magic_link_callback/:token/session with no user for the address" do
    it "spends the token and refuses" do
      token = MagicLinkToken.create_for_email("nobody@example.com")

      post magic_link_callback_session_path(token)

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("magic_link_callbacks.show.invalid"))
      expect(MagicLinkToken.find_valid(token)).to be_nil
    end
  end
end
