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
      it "flips quiet_hours.enabled in the JSONB column" do
        expect(user.preferences.notification_preferences.dig("quiet_hours", "enabled")).to eq(false)

        patch account_notification_preferences_path, params: {
          notification_preferences: { quiet_hours: { enabled: "true" } }
        }

        expect(user.preferences.reload.notification_preferences.dig("quiet_hours", "enabled")).to eq(true)
      end

      it "deep-merges a single notification_types toggle and preserves siblings" do
        original_types = user.preferences.notification_preferences["notification_types"].deep_dup

        patch account_notification_preferences_path, params: {
          notification_preferences: {
            notification_types: { workspace_activity: "false" }
          }
        }

        prefs = user.preferences.reload.notification_preferences
        expect(prefs.dig("notification_types", "workspace_activity")).to eq(false)
        # Every other type untouched.
        %w[security account_access project_activity billing].each do |other|
          expect(prefs.dig("notification_types", other)).to eq(original_types[other])
        end
      end

      it "updates email.frequency and recomputes digest_next_due_at" do
        user.preferences.update!(digest_next_due_at: 1.year.from_now)
        original_due = user.preferences.digest_next_due_at

        patch account_notification_preferences_path, params: {
          notification_preferences: {
            delivery_methods: { email: { frequency: "weekly" } }
          }
        }

        user.preferences.reload
        expect(user.preferences.notification_preferences.dig("delivery_methods", "email", "frequency")).to eq("weekly")
        # Recomputed against user timezone — should be in the near future
        # (cadence is daily/weekly), not the 1-year-out value we seeded.
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
          params: { notification_preferences: { quiet_hours: { enabled: "true" } } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      # SR feedback on auto-submit: previously the turbo_stream body was
      # empty so screen readers got no signal that the toggle took effect.
      # The response now updates the page-level aria-live region with a
      # confirmation announcement.
      it "the turbo_stream response updates the live region with a save announcement" do
        patch account_notification_preferences_path,
          params: { notification_preferences: { quiet_hours: { enabled: "true" } } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.body).to include('target="notifications-live"')
        expect(response.body).to include(I18n.t("notifications.preferences.update.saved_announcement"))
      end

      describe "v2 input validation" do
        # The plan calls for 8 new validation tests covering quiet_hours,
        # email.frequency, and notification_types. Each invalid shape must
        # return 422 and leave the JSONB untouched (no half-applied changes).

        it "accepts a valid HH:MM start/end pair for quiet_hours" do
          patch account_notification_preferences_path, params: {
            notification_preferences: {
              quiet_hours: { enabled: "true", start: "22:00", end: "07:00" }
            }
          }

          qh = user.preferences.reload.notification_preferences["quiet_hours"]
          expect(qh["start"]).to eq("22:00")
          expect(qh["end"]).to eq("07:00")
          expect(qh["enabled"]).to eq(true)
        end

        it "rejects an invalid quiet_hours.start format with 422" do
          patch account_notification_preferences_path, params: {
            notification_preferences: {
              quiet_hours: { start: "25:00" }
            }
          }

          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "rejects a non-HH:MM quiet_hours.end with 422" do
          patch account_notification_preferences_path, params: {
            notification_preferences: {
              quiet_hours: { end: "7am" }
            }
          }

          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "stores allow_urgent without behavioral side effects (currently inert v1)" do
          patch account_notification_preferences_path, params: {
            notification_preferences: {
              quiet_hours: { allow_urgent: "false" }
            }
          }

          qh = user.preferences.reload.notification_preferences["quiet_hours"]
          expect(qh["allow_urgent"]).to eq(false)
          # No code path reads allow_urgent in v1 (decision #13) — pinning
          # the storage round-trip without asserting behavior.
        end

        it "accepts each valid email.frequency value" do
          %w[instant daily weekly].each do |freq|
            patch account_notification_preferences_path, params: {
              notification_preferences: {
                delivery_methods: { email: { frequency: freq } }
              }
            }

            expect(user.preferences.reload.notification_preferences.dig("delivery_methods", "email", "frequency"))
              .to eq(freq)
          end
        end

        it "rejects an invalid email.frequency value with 422" do
          patch account_notification_preferences_path, params: {
            notification_preferences: {
              delivery_methods: { email: { frequency: "monthly" } }
            }
          }

          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "rejects notification_types with an unknown category key with 422" do
          patch account_notification_preferences_path, params: {
            notification_preferences: {
              notification_types: { mystery_category: "true" }
            }
          }

          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "leaves the JSONB untouched when validation rejects the request" do
          original = user.preferences.notification_preferences.deep_dup

          patch account_notification_preferences_path, params: {
            notification_preferences: {
              delivery_methods: { email: { frequency: "monthly" } }
            }
          }

          expect(response).to have_http_status(:unprocessable_entity)
          expect(user.preferences.reload.notification_preferences).to eq(original)
        end
      end
    end
  end
end
