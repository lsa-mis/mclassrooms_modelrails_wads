require "rails_helper"

RSpec.describe "Sign up", type: :system do
  before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

  it "allows a visitor to create an account" do
    visit new_registration_path

    fill_in I18n.t("registrations.new.email_label"), with: "newuser@example.com"
    fill_in I18n.t("registrations.new.first_name_label"), with: "Jane"
    fill_in I18n.t("registrations.new.last_name_label"), with: "Doe"
    fill_in I18n.t("registrations.new.password_label"), with: "SecureP@ssw0rd123!"
    fill_in I18n.t("registrations.new.password_confirmation_label"), with: "SecureP@ssw0rd123!"

    click_button I18n.t("registrations.new.submit")

    expect(page).to have_text(I18n.t("registrations.create.success"))
  end
end
