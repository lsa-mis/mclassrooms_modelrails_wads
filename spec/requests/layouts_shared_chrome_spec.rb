require "rails_helper"

# Guards the layout chrome shared between application.html.erb and
# settings.html.erb via shared/_layout_head and shared/_layout_tail (#146):
# both layouts render the same head, skip link, and tail.
#
# Turbo morph (#327) is enabled for the settings hub only: the settings layout
# provides the turbo-refresh-method meta through the shared head's yield :head
# hook, while the application layout does not.
RSpec.describe "Shared layout chrome", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  shared_examples "shared layout chrome" do
    it "renders the shared head, skip link, and notifications live region" do
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('meta[name="description"]')).not_to be_nil
      expect(doc.at_css('link[rel="manifest"]')).not_to be_nil
      expect(doc.at_css('a[href="#main-content"]')).not_to be_nil
      expect(doc.at_css('#notifications-live[aria-live="polite"]')).not_to be_nil
    end
  end

  context "application layout (non-settings page)" do
    before { get root_path }

    include_examples "shared layout chrome"

    it "does not enable Turbo morph (no refresh-method meta)" do
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('meta[name="turbo-refresh-method"]')).to be_nil
    end
  end

  context "settings layout" do
    before { get edit_settings_theme_preference_path }

    include_examples "shared layout chrome"

    it "enables Turbo morph for the settings hub (#327)" do
      doc = Nokogiri::HTML(response.body)
      meta = doc.at_css('meta[name="turbo-refresh-method"]')
      expect(meta).not_to be_nil
      expect(meta["content"]).to eq("morph")
    end
  end
end
