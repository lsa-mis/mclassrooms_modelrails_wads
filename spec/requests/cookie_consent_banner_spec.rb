require "rails_helper"

# The MiClassrooms override of biscuit-rails' banner
# (app/views/biscuit/banner/_banner.html.erb): a reject-emphasized first-visit
# layout and an edit-only manage layout, chosen server-side by whether a choice
# was already recorded. Guards the panel-approved consent UX + the compliance
# rules (privacy-forward default, no pre-checked non-essential boxes).
RSpec.describe "Cookie consent banner", type: :request do
  def banner
    Capybara.string(response.body).find("[data-controller='biscuit']")
  end

  describe "first visit (no choice recorded)" do
    before { get new_session_path }

    it "emphasizes Reject non-essential as the primary action" do
      reject = banner.find("[data-action~='click->biscuit#rejectAll']")
      expect(reject[:class]).to include("biscuit-btn--primary")
      expect(reject).to have_text("Reject non-essential")
    end

    it "keeps Accept all as the quiet secondary action" do
      accept = banner.find("[data-action~='click->biscuit#acceptAll']")
      expect(accept[:class]).to include("biscuit-btn--secondary")
    end

    it "does NOT pre-check any non-essential category (consent is affirmative)" do
      expect(banner).to have_no_css("[data-biscuit-target='categoryCheckbox'][checked]", visible: :all)
    end
  end

  describe "manage mode (consent already recorded)" do
    before do
      cookies["biscuit_consent"] =
        { v: 1, consented_at: "2026-07-14T00:00:00Z",
          categories: { analytics: true, preferences: false, marketing: false, necessary: true } }.to_json
      get new_session_path
    end

    it "drops the Accept / Reject / Manage shortcut buttons" do
      expect(banner).to have_no_css("[data-action~='click->biscuit#acceptAll']", visible: :all)
      expect(banner).to have_no_css("[data-action~='click->biscuit#rejectAll']", visible: :all)
      expect(banner).to have_no_css("[data-action~='click->biscuit#togglePreferences']", visible: :all)
    end

    it "shows the editable checkboxes + Save, reflecting the saved choice" do
      expect(banner).to have_css("[data-action~='click->biscuit#savePreferences']", visible: :all)
      expect(banner).to have_css("[data-category='analytics'][checked]", visible: :all)
      expect(banner).to have_no_css("[data-category='marketing'][checked]", visible: :all)
    end
  end
end
