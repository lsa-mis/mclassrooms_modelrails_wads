require "rails_helper"

# Reproduction / regression for the Biscuit cookie-consent RECORDING flow.
# The existing footer_cookies_spec only SIMULATES the post-consent state via
# execute_script; the real click -> POST /biscuit/consent -> biscuit_consent
# cookie -> banner-stays-hidden loop had no coverage, and both guards it rides
# on (forgery protection + CSP) are disabled/report-only in test, so a broken
# recording would ship green.
RSpec.describe "Cookie consent recording (Biscuit)", type: :system do
  it "records the choice on Accept and keeps the banner dismissed across reloads" do
    visit root_path

    # The banner is wired to the biscuit Stimulus controller with an accept action.
    expect(page).to have_css("[data-controller='biscuit']")
    accept = find("button[data-action~='click->biscuit#acceptAll']")

    accept.click

    # The controller's #post fires the fetch; on response.ok it hides the banner.
    expect(page).to have_css("[data-biscuit-target='banner'][hidden]", visible: :all, wait: 5)

    # Reload: the server reads the biscuit_consent cookie and renders the banner
    # already-consented (hidden). If the choice was not recorded, the banner
    # comes back visible here.
    visit root_path
    expect(page).to have_css("[data-biscuit-target='banner'][hidden]", visible: :all, wait: 5)
    expect(page).to have_no_css("[data-biscuit-target='banner']:not([hidden])")
  end
end
