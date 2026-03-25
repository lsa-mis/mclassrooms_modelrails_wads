require "rails_helper"

RSpec.describe "Static pages", type: :system do
  describe "home page" do
    it "has a skip-to-content link" do
      visit root_path
      expect(page).to have_css("a[href='#main-content']", visible: :all)
    end

    it "has a main content landmark" do
      visit root_path
      expect(page).to have_css("main#main-content")
    end

    it "has a lang attribute on html" do
      visit root_path
      expect(page).to have_css("html[lang='en']")
    end
  end

  %w[about privacy contact].each do |page_name|
    describe "#{page_name} page" do
      it "renders successfully" do
        visit send(:"#{page_name}_path")
        expect(page).to have_css("h1")
      end
    end
  end
end
