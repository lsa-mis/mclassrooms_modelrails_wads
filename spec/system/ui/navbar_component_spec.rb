# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the navbar component.
#
# The hamburger is `md:hidden` — visible only below the md breakpoint — so we resize the window
# to a MOBILE viewport (375×800) before exercising the disclosure: toggle opens the menu (syncs
# aria-expanded), Escape closes + returns focus to the toggle, an outside click closes. NOTE:
# per-spec axe runs AA locally; the AAA 7:1 audit is the CI-only wcag2aaa hook.
RSpec.describe "Navbar component accessibility", type: :system do
  before do
    visit "/rails/view_components/ui/navbar_component/basic"
    page.current_window.resize_to(375, 800)
  end

  def toggle
    find("button[data-navbar-target='toggle']")
  end

  it "renders the nav and the open mobile menu passes AAA in both themes" do
    expect(page).to have_css("nav[aria-label='Main']")
    expect(toggle["aria-expanded"]).to eq("false")
    expect(page).to have_css("[data-navbar-target='menu']", visible: :hidden)

    toggle.click
    expect(toggle["aria-expanded"]).to eq("true")
    expect(page).to have_css("[data-navbar-target='menu']", visible: :visible)

    scope = [ "nav" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "the hamburger toggles the mobile menu and syncs aria-expanded" do
    expect(page).to have_css("[data-navbar-target='menu']", visible: :hidden)

    toggle.click
    expect(page).to have_css("[data-navbar-target='menu']", visible: :visible)
    expect(toggle["aria-expanded"]).to eq("true")

    toggle.click
    expect(page).to have_css("[data-navbar-target='menu']", visible: :hidden)
    expect(toggle["aria-expanded"]).to eq("false")
  end

  it "Escape closes the menu and returns focus to the hamburger" do
    toggle.click
    expect(page).to have_css("[data-navbar-target='menu']", visible: :visible)

    page.send_keys(:escape)
    expect(page).to have_css("[data-navbar-target='menu']", visible: :hidden)
    expect(toggle["aria-expanded"]).to eq("false")
    expect(page.evaluate_script("document.activeElement.getAttribute('data-navbar-target')")).to eq("toggle")
  end

  it "an outside click closes the menu" do
    toggle.click
    expect(page).to have_css("[data-navbar-target='menu']", visible: :visible)

    cdp_click_at(10, 760)
    expect(page).to have_css("[data-navbar-target='menu']", visible: :hidden)
    expect(toggle["aria-expanded"]).to eq("false")
  end
end
