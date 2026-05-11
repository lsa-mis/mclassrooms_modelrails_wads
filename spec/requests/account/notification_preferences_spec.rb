require "rails_helper"

RSpec.describe "Account Notification Preferences", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /account/notification_preferences/edit to sign in" do
      get edit_account_notification_preferences_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects PATCH /account/notification_preferences to sign in" do
      patch account_notification_preferences_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }

    before do
      sign_in(user)
      user.create_preferences!(timezone: "America/New_York") unless user.preferences
    end

    describe "GET /account/notification_preferences/edit" do
      it "returns 200 and renders the edit page" do
        get edit_account_notification_preferences_path
        expect(response).to have_http_status(:ok)
      end

      # Phase 0.5: the page surfaces the user's currently-stored timezone
      # prominently, with a native <select> for the Change action. The
      # form posts to the same timezone endpoint with override=true so it
      # bypasses the beacon's no-overwrite guard.
      it "renders the detected/stored timezone with a Change action that posts to the timezone endpoint with override=true" do
        user.preferences.update!(timezone: "America/Chicago")

        get edit_account_notification_preferences_path

        expect(response.body).to include("America/Chicago")
        expect(response.body).to include(%Q(action="#{account_preferences_timezone_path}"))
        expect(response.body).to include(%Q(name="override" value="true"))
      end

      it "renders the timezone select with regional optgroups (Americas, Europe, etc.)" do
        get edit_account_notification_preferences_path

        expect(response.body).to include(%Q(<optgroup label="Americas">))
        expect(response.body).to include(%Q(<optgroup label="Europe">))
        expect(response.body).to include(%Q(<optgroup label="Pacific">))
      end
    end

    describe "PATCH /account/notification_preferences" do
      it "flips the do_not_disturb flag in the JSONB column" do
        expect(user.preferences.notification_preferences["do_not_disturb"]).to eq(false)

        patch account_notification_preferences_path, params: {
          notification_preferences: { do_not_disturb: "true" }
        }

        expect(user.preferences.reload.notification_preferences["do_not_disturb"]).to eq(true)
      end

      it "deep-merges a single category × channel toggle and preserves siblings" do
        original_categories = user.preferences.notification_preferences["categories"].deep_dup

        patch account_notification_preferences_path, params: {
          notification_preferences: {
            categories: { workspace_activity: { email: "true" } }
          }
        }

        prefs = user.preferences.reload.notification_preferences
        expect(prefs.dig("categories", "workspace_activity", "email")).to eq(true)
        # Every other key untouched.
        expect(prefs.dig("categories", "workspace_activity", "in_app")).to eq(original_categories.dig("workspace_activity", "in_app"))
        expect(prefs.dig("categories", "workspace_activity", "digest")).to eq(original_categories.dig("workspace_activity", "digest"))
        expect(prefs["categories"].keys.sort).to eq(original_categories.keys.sort)
        %w[security account_access project_activity billing].each do |other|
          expect(prefs.dig("categories", other)).to eq(original_categories[other])
        end
      end

      it "updates digest config and recomputes digest_next_due_at" do
        user.preferences.update!(digest_next_due_at: 1.year.from_now)
        original_due = user.preferences.digest_next_due_at

        patch account_notification_preferences_path, params: {
          notification_preferences: {
            digest: { cadence: "weekly", hour_local: "14" }
          }
        }

        user.preferences.reload
        expect(user.preferences.notification_preferences.dig("digest", "cadence")).to eq("weekly")
        expect(user.preferences.notification_preferences.dig("digest", "hour_local")).to eq(14)
        # Recomputed against user timezone — should be near-future, not the
        # 1-year-out value we seeded.
        expect(user.preferences.digest_next_due_at).to be < 14.days.from_now
        expect(user.preferences.digest_next_due_at).not_to eq(original_due)
      end

      it "stores retention_days when an allowed value is provided" do
        patch account_notification_preferences_path, params: {
          notification_preferences: { retention_days: "30" }
        }

        expect(user.preferences.reload.notification_preferences["retention_days"]).to eq(30)
      end

      it "stores nil retention_days for the 'never' option" do
        patch account_notification_preferences_path, params: {
          notification_preferences: { retention_days: "" }
        }

        expect(user.preferences.reload.notification_preferences["retention_days"]).to be_nil
      end

      it "rejects retention_days outside the allowed list with 422" do
        patch account_notification_preferences_path, params: {
          notification_preferences: { retention_days: "999" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "responds with turbo_stream when requested" do
        patch account_notification_preferences_path,
          params: { notification_preferences: { do_not_disturb: "true" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      # SR feedback on auto-submit: previously the turbo_stream body was
      # empty so screen readers got no signal that the toggle took effect.
      # The response now updates the page-level aria-live region with a
      # confirmation announcement.
      it "the turbo_stream response updates the live region with a save announcement" do
        patch account_notification_preferences_path,
          params: { notification_preferences: { do_not_disturb: "true" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.body).to include('target="notifications-live"')
        expect(response.body).to include(I18n.t("notifications.preferences.update.saved_announcement"))
      end
    end
  end
end
