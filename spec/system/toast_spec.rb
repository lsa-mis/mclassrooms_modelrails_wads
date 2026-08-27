require "rails_helper"

RSpec.describe "Toast notification system", type: :system do
  let(:user) { create(:user) }

  def trigger_login_failure
    # The lookup action now sends a magic link; reach the password form directly.
    visit session_password_form_path(email_address: user.email_address)
    fill_in I18n.t("sessions.password_form.password_label"), with: "wrongpassword"
    click_button I18n.t("sessions.password_form.submit")
  end

  def dismiss_cookie_banner
    page.execute_script(<<~JS)
      document.querySelectorAll('[data-controller="biscuit"]').forEach(el => el.remove());
    JS
  end

  # #683: a live region must exist and be registered BEFORE content arrives —
  # a region inserted WITH its content (the appended toast carrying its own
  # aria-live) is silently dropped by AT. The STABLE containers own the
  # announcement semantics.
  describe "stable live-region containers (#683)" do
    it "both toast containers are live regions before any toast exists" do
      sign_in_via_form(user)
      expect(page.find("#toast-pills", visible: :all)["aria-live"]).to eq("polite")
      expect(page.find("#toast-cards", visible: :all)["aria-live"]).to eq("assertive")
    end
  end

  describe "pill toasts (success/info)" do
    it "appears as a pill in the top-center container" do
      sign_in_via_form(user)
      expect(page).to have_css("#toast-pills [data-controller='toast-pill']")
    end

    it "keeps role=status but no own live attrs — the container announces (#683)" do
      sign_in_via_form(user)
      pill = find("[data-controller='toast-pill']")
      expect(pill["role"]).to eq("status")
      expect(pill["aria-live"]).to be_nil
    end

    it "includes a progress bar" do
      sign_in_via_form(user)
      expect(page).to have_css("[data-toast-pill-target='progress']")
    end

    it "auto-dismisses after timeout" do
      sign_in_via_form(user)
      toast = find("[data-controller='toast-pill']")
      # Budget derived from the toast's own configuration — timeout + stagger
      # Stimulus values (defaults mirror toast_pill_controller.js) + dismiss
      # animation margin — instead of the previous guessed-ceiling wait: 18,
      # which also billed its full 18s on any genuine failure (#857).
      timeout_ms = (toast["data-toast-pill-timeout-value"] || 5000).to_i
      stagger_ms = (toast["data-toast-pill-stagger-value"] || 2000).to_i
      budget = (timeout_ms + stagger_ms) / 1000.0 + 2
      expect(page).to have_no_css("[data-controller='toast-pill']", wait: budget)
    end

    it "does not overlap the user menu dropdown" do
      sign_in_via_form(user)
      expect(page).to have_css("[data-controller='toast-pill']")

      # Open user menu
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)

      # Pill should be in toast-pills (top-center), menu in top-right — no overlap
      pill_container = find("#toast-pills")
      menu = find("#user-menu")
      expect(pill_container).to be_truthy
      expect(menu).to be_truthy
    end
  end

  describe "card toasts (warning/error)" do
    it "renders an error flash as a card in the bottom-center container" do
      trigger_login_failure
      expect(page).to have_css("#toast-cards [data-controller='toast-card']")
    end

    it "keeps role=alert but no own live attrs — the container announces (#683)" do
      trigger_login_failure
      card = find("[data-controller='toast-card']")
      expect(card["role"]).to eq("alert")
      expect(card["aria-live"]).to be_nil
    end

    it "persists until manually dismissed" do
      # Negative assertion (no auto-dismiss), made structural instead of
      # temporal: the old version slept 6 wall-clock seconds to outwait a
      # hypothetical ~5s dismiss timer (#453). A reintroduced auto-dismiss
      # must schedule its long setTimeout when the toast connects, so record
      # every long timer scheduled from page load and assert none exist while
      # the card is up — same regression caught, zero seconds spent.
      cdp_add_init_script(<<~JS)
        window.__longTimers = [];
        const realSetTimeout = window.setTimeout;
        window.setTimeout = function(fn, delay, ...args) {
          if (delay >= 1000) window.__longTimers.push(delay);
          return realSetTimeout(fn, delay, ...args);
        };
      JS
      trigger_login_failure
      expect(page).to have_css("[data-controller='toast-card']")
      expect(page.evaluate_script("window.__longTimers")).to eq([]),
        "a long timer was scheduled while the persistent toast was mounting — " \
        "auto-dismiss must not come back (toasts persist until dismissed)"
      expect(page).to have_css("[data-controller='toast-card']")
    end

    it "dismisses when close button is clicked" do
      trigger_login_failure
      expect(page).to have_css("[data-controller='toast-card']")
      dismiss_cookie_banner
      find("[data-controller='toast-card'] button[aria-label]").click
      expect(page).to have_no_css("[data-controller='toast-card']")
    end

    it "close button is keyboard accessible" do
      trigger_login_failure
      expect(page).to have_css("[data-controller='toast-card']")
      dismiss_cookie_banner
      close_button = find("[data-controller='toast-card'] button[aria-label]")
      close_button.send_keys(:enter)
      expect(page).to have_no_css("[data-controller='toast-card']")
    end
  end
end
