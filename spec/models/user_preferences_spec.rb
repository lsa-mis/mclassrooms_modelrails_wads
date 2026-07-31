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
end
