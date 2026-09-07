require "rails_helper"

RSpec.describe "Connected account verification", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:auth) do
    user.authentications.create!(
      provider: "google", uid: "uid-system-spec", email: "sammy.work@gmail.com", verified_at: nil
    )
  end

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(axe_options)).to(be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}")
  end

  before { sign_in_via_form(user) }

  it "renders the confirmation accessibly in both themes and verifies nothing on GET" do
    token = auth.generate_token_for(:email_verification)
    visit settings_connected_account_verification_path(token: token)

    expect(page).to have_text(I18n.t("settings.connected_account_verifications.show.title"))
    expect(page).to have_button(
      I18n.t("settings.connected_account_verifications.show.button", email: auth.email, provider: auth.display_provider)
    )
    expect(page).to have_link(I18n.t("settings.connected_account_verifications.show.cancel"))
    expect_aaa_in_both_themes

    expect(auth.reload).not_to be_verified
  end

  it "verifies via keyboard activation and shows the in-document success banner on the index" do
    token = auth.generate_token_for(:email_verification)
    visit settings_connected_account_verification_path(token: token)

    find("button[type=submit]").send_keys(:enter)

    expect(page).to have_current_path(settings_connected_accounts_path)
    expect(page).to have_text(
      I18n.t("settings.connected_accounts.index.verified_banner", email: auth.email)
    )
    expect(auth.reload).to be_verified
  end
end
