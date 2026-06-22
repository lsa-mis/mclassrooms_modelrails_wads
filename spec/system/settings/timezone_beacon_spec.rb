# frozen_string_literal: true

require "rails_helper"

# Layout-level beacon that captures the browser-detected IANA timezone on
# layout connect. The controller reads
# `Intl.DateTimeFormat().resolvedOptions().timeZone` and PATCHes the
# timezone endpoint. Idempotent at the server side — never overwrites an
# existing user choice.
RSpec.describe "Timezone beacon (Stimulus + layout connect)", type: :system, js: true do
  let(:password) { "BeaconUser#42!" }
  let(:user)     { create(:user, password: password) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
  end

  describe "round-trip: fresh sign-in with nil timezone" do
    it "writes the browser-detected IANA timezone to user_preferences.timezone" do
      user.create_preferences!(timezone: nil)

      sign_in_via_form(user)

      # The beacon fires on layout connect. Give it a moment to round-trip.
      Timeout.timeout(5) do
        loop do
          break if user.preferences.reload.timezone.present?
          sleep 0.1
        end
      end

      expect(user.preferences.reload.timezone).to be_present
      # Test browsers default to UTC, but the IANA name should look
      # IANA-shaped (Region/City or "UTC" itself).
      tz = user.preferences.timezone
      expect(tz).to match(%r{\A([A-Z][A-Za-z_]+/[A-Z][A-Za-z_/]+|UTC|GMT)\z})
    end
  end

  describe "idempotency: explicit timezone preserved" do
    it "does NOT overwrite an explicitly-set timezone" do
      user.create_preferences!(timezone: "Europe/London")

      sign_in_via_form(user)

      # Give the beacon a chance to (incorrectly) fire and clobber. If the
      # contract holds, the explicit value remains.
      sleep 1.0
      expect(user.preferences.reload.timezone).to eq("Europe/London")
    end
  end

  describe "unauthenticated pages: beacon does not fire" do
    it "does not POST to the timezone endpoint on the sign-in page" do
      # The beacon is gated by `<% if authenticated? %>` in the layout, so
      # it should NOT render its data attributes on anonymous pages.
      visit new_session_path
      expect(page).to have_no_css('[data-controller~="timezone-beacon"]')
    end
  end
end
