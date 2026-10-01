# frozen_string_literal: true

require "rails_helper"

# MClassrooms' header: U-M Blue bar, maize rule and M, light-blue current-page underline.
RSpec.describe "Branded header", type: :system do
  # Find a Room needs the shared directory workspace; setup as in find_a_room_spec.
  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }
  let(:user) { create(:user) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    sign_in_via_form(user)
  end

  def computed(selector, property, pseudo: nil)
    page.evaluate_script(
      "getComputedStyle(document.querySelector(#{selector.to_json}), #{pseudo.to_json})[#{property.to_json}]"
    )
  end

  def find_a_room_link = "header a[href='#{find_a_room_path}']"
  def indicator = "oklch(0.807 0.101 250.4)"

  it "paints the bar U-M Blue over a 4px maize rule" do
    visit root_path

    expect(computed("header", "backgroundColor")).to eq("oklch(0.271 0.08 251.6)")
    expect(computed("header", "borderBottomColor")).to eq("oklch(0.863 0.176 89.8)")
    expect(computed("header", "borderBottomWidth")).to eq("4px")
  end

  it "underlines Find a Room in light blue only on the Find a Room page" do
    visit find_a_room_path

    expect(page).to have_css("#{find_a_room_link}[aria-current='page']")
    expect(computed(find_a_room_link, "boxShadow")).to include(indicator)

    visit root_path

    expect(page).to have_css(find_a_room_link)
    expect(page).to have_no_css("#{find_a_room_link}[aria-current]")
    expect(computed(find_a_room_link, "boxShadow")).to eq("none")
  end

  it "sets the wordmark's M in maize" do
    visit root_path

    expect(computed("header a[href='#{root_path}'] span", "color", pseudo: "::first-letter"))
      .to eq("oklch(0.863 0.176 89.8)")
  end

  it "stays AAA in both themes" do
    visit find_a_room_path

    expect(page).to have_css("#{find_a_room_link}[aria-current='page']")
    expect_aaa_in_both_themes(include: "header")
  end
end

RSpec.describe "Branded header, signed out", type: :system do
  it "keeps the Sign in link readable on the U-M Blue bar in both themes" do
    visit root_path

    expect(page).to have_link(I18n.t("navigation.sign_in"), href: new_session_path)
    expect_aaa_in_both_themes(include: "header")
  end
end
