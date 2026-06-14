require "rails_helper"

# Timezone beacon endpoint. The Stimulus controller on the layout fires
# this on connect with the browser-detected IANA zone. The endpoint is
# idempotent by default — writes only when timezone is nil — so the beacon
# never clobbers an explicit user choice. Pass `override: true` from the
# preferences page's Change action to overwrite an existing value.
RSpec.describe "Account Preferences — Timezone beacon", type: :request do
  describe "unauthenticated access" do
    it "redirects PATCH /account/preferences/timezone to sign in" do
      patch account_preferences_timezone_path, params: { timezone: "America/New_York" }
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }

    before { sign_in(user) }

    describe "PATCH /account/preferences/timezone (default beacon mode)" do
      it "writes the timezone when current value is nil" do
        user.create_preferences!(timezone: nil)

        patch account_preferences_timezone_path, params: { timezone: "America/New_York" }

        expect(user.preferences.reload.timezone).to eq("America/New_York")
        expect(response).to have_http_status(:no_content)
      end

      it "is a no-op when timezone is already set (preserves explicit user choice)" do
        user.create_preferences!(timezone: "Europe/London")

        patch account_preferences_timezone_path, params: { timezone: "America/New_York" }

        expect(user.preferences.reload.timezone).to eq("Europe/London")
        expect(response).to have_http_status(:no_content)
      end

      it "creates a preferences row if the user has none, then writes the timezone" do
        expect(user.preferences).to be_nil

        patch account_preferences_timezone_path, params: { timezone: "America/Chicago" }

        expect(user.reload.preferences&.timezone).to eq("America/Chicago")
      end

      it "rejects an invalid IANA timezone identifier with 422" do
        user.create_preferences!(timezone: nil)

        patch account_preferences_timezone_path, params: { timezone: "Not/A_Real_Zone" }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.preferences.reload.timezone).to be_nil
      end

      it "rejects a missing timezone param with 422" do
        user.create_preferences!(timezone: nil)

        patch account_preferences_timezone_path, params: {}

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "PATCH with override: true (preferences-page Change action)" do
      it "overwrites an existing timezone when override is true" do
        user.create_preferences!(timezone: "Europe/London")

        patch account_preferences_timezone_path,
          params: { timezone: "America/Los_Angeles", override: "true" }

        expect(user.preferences.reload.timezone).to eq("America/Los_Angeles")
      end

      it "still validates the IANA identifier when override is true" do
        user.create_preferences!(timezone: "Europe/London")

        patch account_preferences_timezone_path,
          params: { timezone: "Not/Real", override: "true" }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.preferences.reload.timezone).to eq("Europe/London")
      end

      # The explicit-user-save path returns a Turbo Stream that closes the
      # <details> drawer + re-renders the timezone summary + announces the
      # save via aria-live. The beacon path still returns 204 (asserted
      # above) since it has no UI to update.
      it "responds with turbo_stream when the override path requests it" do
        user.create_preferences!(timezone: "Europe/London")

        patch account_preferences_timezone_path,
          params: { timezone: "America/Los_Angeles", override: "true" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("America/Los_Angeles")
        expect(response.body).to include(I18n.t("notifications.preferences.timezone.saved_announcement"))
      end
    end

    # Pundit gates the endpoint. Stubbing the policy to deny proves
    # authorize is actually being invoked — applies to both the beacon
    # path AND the explicit-user path (same controller action).
    describe "Pundit authorization wiring" do
      it "raises NotAuthorizedError → redirects when the policy denies update" do
        user.create_preferences!(timezone: "Europe/London")
        allow(Account::TimezonePolicy).to receive(:new)
          .and_return(instance_double(Account::TimezonePolicy, update?: false))

        patch account_preferences_timezone_path,
          params: { timezone: "America/New_York" }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
        expect(user.preferences.reload.timezone).to eq("Europe/London")
      end
    end
  end
end
