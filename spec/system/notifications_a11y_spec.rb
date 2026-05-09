require "rails_helper"

RSpec.describe "Notifications a11y plumbing", type: :system do
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

  describe "aria-live region" do
    it "renders an empty polite-atomic live region for announcement updates" do
      sign_in_via_form(user)
      visit root_path

      # `visible: :all` because `.sr-only` clips the element off-screen for
      # sighted users; assistive tech still reads it.
      live = find("#notifications-live", visible: :all)
      expect(live["aria-live"]).to eq("polite")
      expect(live["aria-atomic"]).to eq("true")
      expect(live.text).to eq("")
    end
  end

  describe "bell frame turbo-stream subscription" do
    it "renders a turbo-stream-from subscription in the layout for authenticated users" do
      sign_in_via_form(user)
      visit root_path

      expect(page).to have_css("turbo-cable-stream-source", visible: :all)
      expect(page).to have_css("turbo-frame#notifications_bell_frame")
    end

    it "does NOT render the subscription on unauthenticated pages" do
      visit new_session_path

      expect(page).to have_no_css("turbo-cable-stream-source")
    end
  end
end
