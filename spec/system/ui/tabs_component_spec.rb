# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility + behavior proof for the tabs component.
#
# APG tabs (automatic activation): ←/→ move focus AND reveal the panel (wrap, skip-disabled),
# Home/End jump, click activates, panels are focusable (tabindex=0). NOTE: per-spec axe runs
# AA locally; the AAA 7:1 audit is the CI-only wcag2aaa hook.
RSpec.describe "Tabs component accessibility", type: :system do
  before { visit "/rails/view_components/ui/tabs_component/basic" }

  def tab(text)
    find("button[role='tab']", text: text)
  end

  def focused_text
    page.evaluate_script("document.activeElement.textContent.trim()")
  end

  it "renders tabs and the active panel passes AAA in both themes" do
    expect(page).to have_css("[role='tablist'][aria-label='Account settings']")
    expect(page).to have_css("button[role='tab']", count: 3)
    expect(tab("Profile")["aria-selected"]).to eq("true")
    expect(page).to have_css("[role='tabpanel']:not([hidden])", text: "Manage your public profile")

    scope = [ "[role='tablist']", "[role='tabpanel']:not([hidden])" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "ArrowRight activates the next tab and reveals its panel (wraps)" do
    tab("Profile").click
    expect(tab("Profile")["aria-selected"]).to eq("true")

    page.send_keys(:right) # → Password
    expect(focused_text).to eq("Password")
    expect(tab("Password")["aria-selected"]).to eq("true")
    expect(page).to have_css("[role='tabpanel']:not([hidden])", text: "Change your password")
    expect(page).to have_css("[role='tabpanel']:not([hidden])", count: 1)
  end

  it "ArrowRight skips the disabled tab and wraps to the first" do
    tab("Password").click
    page.send_keys(:right) # skips disabled "Notifications" → wraps to "Profile"
    expect(focused_text).to eq("Profile")
    expect(tab("Profile")["aria-selected"]).to eq("true")
  end

  it "ArrowLeft moves to the previous tab" do
    tab("Password").click
    page.send_keys(:left) # → Profile
    expect(focused_text).to eq("Profile")
    expect(tab("Profile")["aria-selected"]).to eq("true")
  end

  it "Home and End jump to the first and last ENABLED tab" do
    tab("Profile").click
    page.send_keys(:end) # last enabled = Password (Notifications disabled)
    expect(focused_text).to eq("Password")
    expect(tab("Password")["aria-selected"]).to eq("true")

    page.send_keys(:home) # first = Profile
    expect(focused_text).to eq("Profile")
  end

  it "the active panel is focusable (tabindex=0)" do
    expect(page).to have_css("[role='tabpanel']:not([hidden])[tabindex='0']")
  end

  it "only the active tab is in the tab order (roving tabindex)" do
    expect(tab("Profile")["tabindex"]).to eq("0")
    expect(tab("Password")["tabindex"]).to eq("-1")
  end
end
