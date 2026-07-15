require "rails_helper"

# The markdowndocs gem supports per-user mode persistence via two
# initializer lambdas (`user_mode_resolver` + `user_mode_saver`). The
# user_preferences.docs_mode column already exists (migration from
# 2026-03-25); these specs verify the host app's initializer wires the
# lambdas to that column so mode preference survives:
#   - page reloads (the basic "I picked developer" survives navigation)
#   - cookie clears (cookie-only persistence loses the preference on
#     browser-data clear; DB persistence keeps it)
#   - new sessions / new devices (different browser, same user → same
#     preference because it's on the user record, not the cookie)
RSpec.describe "Docs mode persistence (markdowndocs gem)", type: :system do
  let(:password) { "SecureP@ssw0rd123!" }
  let(:user) { create(:user, password: password) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
    visit magic_link_callback_path(token: token)
    expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
  end

  before do
    user.create_preferences!
    sign_in_via_form(user)
  end

  # The mode switcher renders inside the sidebar navigation on doc SHOW
  # pages (the gem's _navigation partial is only embedded in show.html.erb,
  # not index.html.erb). show.html.erb renders the navigation twice (mobile
  # + desktop sidebar) so the switcher appears in the DOM twice; we use
  # `match: :first` since both instances are functionally equivalent.
  it "persists the chosen mode to user_preferences.docs_mode" do
    visit "/docs/developer/getting-started"
    expect(user.preferences.reload.docs_mode).to be_nil

    within first("[data-controller='docs-mode']") do
      click_button I18n.t("markdowndocs.modes.developer")
    end

    Timeout.timeout(5) do
      sleep 0.1 until user.preferences.reload.docs_mode == "developer"
    end
    expect(user.preferences.reload.docs_mode).to eq("developer")
  end

  it "survives cookie clears (the cookie path is now backup, not source of truth)" do
    user.preferences.update!(docs_mode: "developer")

    # Drop all cookies (simulates fresh-browser scenario).
    cdp_clear_cookies
    # Re-establish the session via sign-in.
    sign_in_via_form(user)
    visit "/docs/developer/getting-started"

    # The switcher reflects the DB-stored mode, not the gem default.
    within first("[data-controller='docs-mode']") do
      expect(page).to have_css(
        "button[aria-pressed='true']",
        text: I18n.t("markdowndocs.modes.developer")
      )
    end
  end
end
