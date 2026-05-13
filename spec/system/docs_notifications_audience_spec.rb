require "rails_helper"

# End-to-end coverage of the audience-filtered notification docs:
#   - notifications.md           (audience: guide)
#   - notifications-technical.md (audience: technical)
#
# Both live in the "Features" category. The mode switcher (driven by
# user_preferences.docs_mode, see PR #103) controls which one appears
# on /docs and which one resolves at /docs/:slug.
RSpec.describe "Docs notifications audience filter", type: :system do
  let(:password) { "SecureP@ssw0rd123!" }
  let(:user) { create(:user, password: password) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: password
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  before do
    user.create_preferences!
    sign_in_via_form(user)
  end

  describe "guide mode" do
    before { user.preferences.update!(docs_mode: "guide") }

    it "renders notifications.md and the show page resolves" do
      visit "/docs/notifications"
      expect(page).to have_css("article", text: /Notifications/i)
    end

    it "404s notifications-technical.md (wrong audience)" do
      visit "/docs/notifications-technical"
      expect(page).to have_no_css("article", text: /Notifications — Technical Reference/i)
    end
  end

  describe "technical mode" do
    before { user.preferences.update!(docs_mode: "technical") }

    it "renders notifications-technical.md and the show page resolves" do
      visit "/docs/notifications-technical"
      expect(page).to have_css("article", text: /Notifications — Technical Reference/i)
    end

    it "404s notifications.md (wrong audience)" do
      visit "/docs/notifications"
      # The page title is "Notifications" for the guide doc; in technical
      # mode the slug should not resolve, so the article shouldn't render
      # with the guide doc's content.
      expect(page).to have_no_css("article > p", text: /You'll find the bell icon/i)
    end
  end
end
