require "rails_helper"

RSpec.describe "Magic link registration", type: :system do
  # Pin signup mode to :open for every registration spec. The test boot default is
  # :invite_only, so a stray empty-form POST (a Playwright native-validation race in
  # the missing-name spec) would otherwise hit the create gate and render "invitation only".
  before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

  describe "new user via smart lookup" do
    it "sends a registration link and allows account creation" do
      visit new_session_path

      token = request_magic_link("brand-new@example.com")

      visit magic_link_callback_path(token: token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.new_registration.title"))
      expect(page).to have_text("brand-new@example.com")

      fill_in I18n.t("magic_link_callbacks.new_registration.first_name_label"), with: "Alice"
      fill_in I18n.t("magic_link_callbacks.new_registration.last_name_label"), with: "Wonderland"
      click_button I18n.t("magic_link_callbacks.new_registration.submit")

      expect(page).to have_text(I18n.t("magic_link_callbacks.create.registered"))
      expect(User.find_by(email_address: "brand-new@example.com")).to be_present
    end
  end

  describe "registration with expired token" do
    it "rejects and redirects to sign in" do
      token = MagicLinkToken.create_for_email("expired-reg@example.com")
      MagicLinkToken.find_by(token_digest: MagicLinkToken.digest(token)).update!(expires_at: 1.hour.ago)

      visit magic_link_callback_path(token: token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.invalid"))
    end
  end

  describe "registration with consumed token" do
    it "rejects and redirects to sign in" do
      token = MagicLinkToken.create_for_email("consumed-reg@example.com")
      MagicLinkToken.find_by(token_digest: MagicLinkToken.digest(token)).consume!

      visit magic_link_callback_path(token: token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.invalid"))
    end
  end

  describe "registration with missing name" do
    it "rejects a nameless registration server-side and renders the errors" do
      token = MagicLinkToken.create_for_email("noname@example.com")

      visit magic_link_callback_path(token: token)

      # No field carries a native `required` attribute (TailwindFormBuilder renders
      # aria-required only — see app/form_builders/tailwind_form_builder.rb), so the
      # browser does not block this submit: it reaches the server and User's
      # first_name/last_name presence validations (app/models/user.rb) reject it,
      # re-rendering this same form with the errors below.
      click_button I18n.t("magic_link_callbacks.new_registration.submit")

      expect(page).to have_text(I18n.t("magic_link_callbacks.new_registration.title"))
      expect(User.find_by(email_address: "noname@example.com")).to be_nil

      # role='alert' now uniquely matches the error summary — field-level errors are
      # plain paragraphs (see app/components/ui/form_field_component.rb), not
      # individually live-announced.
      expect(page).to have_selector("[role='alert']", text: I18n.t("modelrails_ui.error_summary.heading", count: 2))
      expect(page).to have_text("#{User.human_attribute_name(:first_name)} #{I18n.t('errors.messages.blank')}")
      expect(page).to have_text("#{User.human_attribute_name(:last_name)} #{I18n.t('errors.messages.blank')}")
    end

    # #683's form leg: UI::ErrorSummaryComponent renders `role="alert"
    # tabindex="-1" autofocus`. Turbo Drive re-honours `[autofocus]` on every
    # 422 re-render (its own restoreFocus step only fires on visits it
    # navigates, not on frame/form-submission re-renders), so the browser's
    # native autofocus processing model is the entire mechanism here — no
    # custom JS to test. Proven end-to-end in Cuprite, not asserted from
    # markup alone, because a `role="alert"`/`tabindex="-1"`/`autofocus`
    # triple that never actually receives focus would pass every markup-only
    # check while leaving assistive tech and keyboard users stranded. Assert
    # by element identity, not role attribute, so this stays strong even if
    # a second role=alert element ever appears on the page.
    it "moves focus to the error summary after a failed submit (422 re-render)" do
      token = MagicLinkToken.create_for_email("focus-noname@example.com")
      visit magic_link_callback_path(token: token)

      click_button I18n.t("magic_link_callbacks.new_registration.submit")

      # GOV.UK's split (#758): the focusable container is not the alert. Focus
      # lands on the container; the alert sits inside it with the heading and
      # the list, so a reader gets the alert's semantics without a second
      # announcement from the focused element carrying the same role.
      expect(page).to have_css("[data-slot='error-summary'][tabindex='-1'] [role='alert']")
      expect(page.evaluate_script(
        "document.activeElement === document.querySelector('[data-slot=\"error-summary\"]')"
      )).to be(true)
      # What Chrome hands assistive technology, not what the markup says.
      expect(ax_property("[data-slot='error-summary']", "focused")).to be(true)
      expect(ax_role("[data-slot='error-summary'] [role='alert']")).to eq("alert")
      expect(ax_name("[data-slot='error-summary'] h2")).to eq(
        I18n.t("modelrails_ui.error_summary.heading", count: 2)
      )
    end

    it "links each error summary item to its field, and the field exists on the page" do
      token = MagicLinkToken.create_for_email("focus-links-noname@example.com")
      visit magic_link_callback_path(token: token)

      click_button I18n.t("magic_link_callbacks.new_registration.submit")

      expect(page).to have_css("[role='alert'] a[href^='#']")

      # Close the loop (#683): follow one anchor's href to a real element id
      # on the page, rather than trusting the href string alone.
      href = page.first("[role='alert'] a[href^='#']")[:href]
      target_id = href.split("#").last
      expect(page).to have_css("##{target_id}")
    end
  end
end
