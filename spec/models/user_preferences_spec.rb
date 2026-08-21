require "rails_helper"

RSpec.describe UserPreferences, type: :model do
  describe "validations" do
    it "allows valid themes" do
      prefs = build(:user_preferences, theme: "light")
      expect(prefs).to be_valid
    end

    it "rejects invalid themes" do
      expect {
        build(:user_preferences, theme: "neon")
      }.to raise_error(ArgumentError)
    end

    # `locale` is user-supplied and gets passed straight to `I18n.t(locale:)`
    # by every notifier. A value outside I18n.available_locales raises
    # I18n::InvalidLocale at render time, so it must never reach the column.
    describe "locale" do
      it "allows nil" do
        expect(build(:user_preferences, locale: nil)).to be_valid
      end

      it "allows a locale the application actually supports" do
        expect(build(:user_preferences, locale: "en")).to be_valid
      end

      it "rejects a locale the application does not support" do
        prefs = build(:user_preferences, locale: "fr")
        expect(prefs).not_to be_valid
        expect(prefs.errors.details[:locale]).to include(hash_including(error: :inclusion))
      end

      it "accepts a locale once a fork registers it" do
        with_available_locale(:fr) do
          expect(build(:user_preferences, locale: "fr")).to be_valid
        end
      end
    end
  end

  describe "theme" do
    it "defaults to system" do
      prefs = UserPreferences.new
      expect(prefs.theme).to eq("system")
    end
  end

  # Single owner of the timezone-name → TimeZone fallback rule. Callers
  # (quiet hours, digest scheduling) must never restate the
  # `TimeZone[name] || Time.zone` dance.
  describe "#time_zone" do
    it "resolves the stored timezone name to an ActiveSupport::TimeZone" do
      prefs = build(:user_preferences, timezone: "America/New_York")
      expect(prefs.time_zone).to eq(ActiveSupport::TimeZone["America/New_York"])
    end

    it "falls back to Time.zone when no timezone is stored" do
      prefs = build(:user_preferences, timezone: nil)
      expect(prefs.time_zone).to eq(Time.zone)
    end

    it "falls back to Time.zone when the stored name is not a recognized zone" do
      prefs = build(:user_preferences, timezone: "Not/AZone")
      expect(prefs.time_zone).to eq(Time.zone)
    end
  end

  describe "#reschedule_digest!" do
    let(:tz) { ActiveSupport::TimeZone["America/New_York"] }

    it "writes digest_next_due_at from the preference object's next_due_at in the user's timezone" do
      prefs = create(:user_preferences, timezone: "America/New_York")
      np = prefs.notification_preferences.deep_dup
      np["delivery_methods"]["email"]["frequency"] = "daily"
      prefs.update!(notification_preferences: np)

      travel_to(tz.parse("2026-04-30 14:00:00")) do
        prefs.reschedule_digest!
        expect(prefs.reload.digest_next_due_at).to eq(tz.parse("2026-05-01 08:00:00"))
      end
    end

    it "does not bump updated_at (fires every digest cycle — must not bust caches)" do
      prefs = create(:user_preferences, timezone: "America/New_York")
      prefs.update_columns(updated_at: 1.day.ago)
      original = prefs.reload.updated_at

      prefs.reschedule_digest!

      expect(prefs.reload.updated_at).to be_within(1.second).of(original)
    end
  end
end
