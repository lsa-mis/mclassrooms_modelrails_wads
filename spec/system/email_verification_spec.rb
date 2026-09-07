require "rails_helper"

RSpec.describe "Email verification", type: :system do
  let(:authentication) { create(:authentication) } # pending (verified_at nil)
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(axe_options)).to(be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}")
  end

  def tab_to_verify_button
    cdp_execute("document.activeElement && document.activeElement.blur()")
    reached = (1..10).any? do
      cdp_press("Tab")
      cdp_evaluate("document.activeElement === document.querySelector('button[type=submit]')")
    end
    raise "could not reach the verify button via Tab navigation" unless reached
  end

  it "renders the confirmation accessibly in both themes and verifies nothing on GET" do
    token = authentication.generate_token_for(:email_verification)
    visit email_verification_path(token: token)

    expect(page).to have_text(I18n.t("email_verifications.show.title"))
    expect(page).to have_button(I18n.t("email_verifications.show.button", email: authentication.user.email_address))
    expect(page).to have_link(I18n.t("email_verifications.show.cancel"))
    expect_aaa_in_both_themes

    expect(authentication.reload).not_to be_verified
  end

  it "verifies and lands the user on the after-authentication page when the button is activated by keyboard" do
    token = authentication.generate_token_for(:email_verification)
    visit email_verification_path(token: token)

    tab_to_verify_button
    cdp_press("Enter")

    expect(page).to have_text(I18n.t("email_verifications.create.success"))
    expect(authentication.reload).to be_verified
  end
end
