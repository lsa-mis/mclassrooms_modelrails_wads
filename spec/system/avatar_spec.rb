require "rails_helper"

RSpec.describe "Avatar management", type: :system do
  let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  def dismiss_cookie_banner
    page.execute_script(<<~JS)
      const banner = document.querySelector('[data-biscuit-target="banner"]');
      if (banner) banner.remove();
    JS
  end

  it "displays initials avatar in profile page by default" do
    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    expect(page).to have_css("span", text: "JD")
  end

  it "shows change avatar button on profile page" do
    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    expect(page).to have_button(I18n.t("account.avatars.edit.change"))
  end

  it "opens avatar modal from profile page" do
    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    click_button I18n.t("account.avatars.edit.change")
    expect(page).to have_css("dialog[open]")
    expect(page).to have_text(I18n.t("account.avatars.edit.title"))
  end

  it "shows source selection when multiple sources are available" do
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
    user.update_columns(avatar_source: "upload")

    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    expect(page).to have_text(I18n.t("account.avatars.source_label"))
  end

  it "does not show source selection with only one source" do
    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_cookie_banner
    expect(page).not_to have_text(I18n.t("account.avatars.source_label"))
  end
end
