# frozen_string_literal: true

require "rails_helper"

# M6 (final-review fix): the SSO-only sign-in page (AuthConfig.sso_only? true)
# was covered structurally by spec/views/sessions/new_spec.rb (which OAuth
# buttons render, which chrome is hidden) and by the CI after-each axe hook on
# whichever system specs happen to visit new_session_path — but no system spec
# ever visited the page in the actual SSO-only, chrome-stripped posture, so
# that specific rendering never got an explicit AAA pass. This closes the gap.
RSpec.describe "SSO-only sign-in page", type: :system do
  before do
    allow(Rails.configuration.x.auth).to receive(:sso_only).and_return(true)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:oauth, :google, :client_id).and_return("google-client-id")
    allow(AuthConfig).to receive(:okta_issuer).and_return("https://miclassrooms-test.okta.com")
  end

  it "renders only the Google + Okta buttons and passes AAA accessibility" do
    visit new_session_path

    # Sanity: this is genuinely the SSO-only posture (mirrors
    # spec/views/sessions/new_spec.rb's structural assertions), not an
    # accidental empty-page pass.
    expect(page).to have_css("form[action='/auth/google_oauth2']")
    expect(page).to have_css("form[action='/auth/okta']")
    expect(page).not_to have_css("form[action='/auth/github']")
    expect(page).not_to have_css("form[action='/session/lookup']")
    expect(page).not_to have_text(I18n.t("sessions.new.passkey_button"))

    # Scoped to wcag2aaa only — the same tag used by the CI after-each hook
    # and every other system-spec axe audit in this suite (see
    # spec/system/passkey_auth_spec.rb for the identical pattern).
    axe_options = { runOnly: { type: "tag", values: [ "wcag2aaa" ] } }
    expect(axe_clean_in_both_themes?(axe_options)).to eq(true),
      "AAA violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
