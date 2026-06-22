# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passwordless-first auth", type: :system do
  # ---------------------------------------------------------------------------
  # Flow 1: brand-new user signs up via magic link — no password anywhere.
  #
  # The app default is :invite_only; open signups are required so the
  # sessions#lookup action allows new-user registration. Use direct config
  # mutation (not allow stubs) so the change is visible on the Rack server
  # thread that Playwright drives — the same pattern used by
  # passwordless_join_link_spec.rb.
  # ---------------------------------------------------------------------------
  describe "brand-new user signs up via magic link, no password set" do
    before do
      @original_signup_mode = Rails.configuration.x.signup.mode
      Rails.configuration.x.signup.mode = :open
    end
    after { Rails.configuration.x.signup.mode = @original_signup_mode }

    it "creates the user without a password_digest" do
      email = "newbie-#{SecureRandom.hex(4)}@example.com"

      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: email
      click_button I18n.t("sessions.new.continue")

      expect(page).to have_text(I18n.t("sessions.check_email.title"))

      token_record = MagicLinkToken.where(email: email).order(:created_at).last
      visit magic_link_callback_path(token: token_record.token)

      fill_in I18n.t("magic_link_callbacks.new_registration.first_name_label"), with: "New"
      fill_in I18n.t("magic_link_callbacks.new_registration.last_name_label"),  with: "Bie"
      click_button I18n.t("magic_link_callbacks.new_registration.submit")

      # Wait for registration to complete before querying the DB.
      expect(page).to have_text(I18n.t("magic_link_callbacks.create.registered"))

      user = User.find_by(email_address: email)
      expect(user).to be_present
      expect(user.has_password?).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # Flow 2: an existing password-holder can fall back to their password.
  #
  # After entering their email, they land on check_email which shows a
  # "use password instead" link. Following it reaches the password form where
  # they can sign in with their stored credential.
  # ---------------------------------------------------------------------------
  describe "existing password-holder signs in via the password fallback" do
    let(:user) { create(:user) } # factory sets password: "SecureP@ssw0rd123!"

    it "follows the secondary link to the password form and signs in" do
      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: user.email_address
      click_button I18n.t("sessions.new.continue")

      # check_email shows the escape hatch for password-holders
      expect(page).to have_text(I18n.t("sessions.check_email.title"))
      expect(page).to have_link(I18n.t("sessions.check_email.use_password"))

      click_link I18n.t("sessions.check_email.use_password")

      # Password form: fill in and submit
      fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
      click_button I18n.t("sessions.password_form.submit")

      expect(page).to have_current_path(root_path)
    end
  end

  # ---------------------------------------------------------------------------
  # Flow 3: forgot-password sends a set_password magic link that lands on the
  # change-password form.
  #
  # The "Forgot your password?" button in password_form.html.erb is a
  # button_to (POST to password_reset_path). Because button_to triggers a
  # Turbo fetch submission, use execute_script to issue a native browser POST
  # so the redirect is followed in the same Playwright session — the same
  # workaround used in invite_only_signup_spec and passwordless_join_link_spec.
  # ---------------------------------------------------------------------------
  describe "forgot-password flow lands on the change-password form" do
    let(:user) { create(:user) }

    it "issues a set_password magic link that redirects to edit_settings_password_path" do
      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: user.email_address
      click_button I18n.t("sessions.new.continue")

      expect(page).to have_text(I18n.t("sessions.check_email.title"))

      click_link I18n.t("sessions.check_email.use_password")

      # Wait for the turbo_frame to update with the password form before proceeding.
      expect(page).to have_field(I18n.t("sessions.password_form.password_label"), wait: 5)

      # "Forgot your password?" is a button_to (POST to /password_reset) inside
      # a turbo_frame. The button_to form carries data-turbo-frame="_top" so
      # Turbo issues a fetch POST and re-renders check_email in the top frame.
      # We submit natively via execute_script to bypass Turbo's submit event
      # listener — HTMLFormElement.prototype.submit skips all event listeners —
      # so the browser issues a real browser-level POST and follows the render.
      page.execute_script(<<~JS)
        const form = document.querySelector("form[action*='password_reset']");
        if (form) { HTMLFormElement.prototype.submit.call(form); }
      JS

      # After the native POST, PasswordResetsController#create re-renders
      # check_email (including "Check your email" heading) inside the layout.
      # Wait for that heading to confirm the server rendered it.
      expect(page).to have_text(I18n.t("sessions.check_email.title"), wait: 10)

      # Extract the set_password token (created by PasswordResetsController).
      token_record = MagicLinkToken.where(email: user.email_address, intent: "set_password")
                                   .order(:created_at).last
      expect(token_record).to be_present

      visit magic_link_callback_path(token: token_record.token)

      expect(page).to have_current_path(edit_settings_password_path)
    end
  end
end
