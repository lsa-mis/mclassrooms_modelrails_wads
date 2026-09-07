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

    # #846. A second POST of the token that just signed this browser in — a
    # double-click, a browser retry, a Capybara re-dispatch on a loaded shard.
    # The token is spent, so `consume!` returns nil and the old code answered
    # "This magic link is invalid or has expired" on the signed-in homepage:
    # the user IS signed in, and is told the opposite. In CI that surfaced as
    # `sign_in_via_form` failing inside an unrelated spec.
    describe "a replayed sign-in POST" do
      it "answers what the first POST answered, not an expiry alert" do
        token = MagicLinkToken.create_for_email(user.email_address)
        post magic_link_callback_session_path(token)

        post magic_link_callback_session_path(token)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_blank
        expect(flash[:notice]).to eq(I18n.t("magic_link_callbacks.show.signed_in"))
      end

      it "honors the spent token's intent, so a replay lands where the first POST did" do
        token = MagicLinkToken.create_for_email(user.email_address, intent: "set_password")
        post magic_link_callback_session_path(token)

        post magic_link_callback_session_path(token)

        expect(response).to redirect_to(edit_settings_password_path)
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
