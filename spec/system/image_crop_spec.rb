require "rails_helper"

RSpec.describe "Image cropping", type: :system do
  let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  def dismiss_banner
    page.execute_script("document.querySelector('[data-biscuit-target=\"banner\"]')?.remove()")
  end

  describe "avatar crop page" do
    before do
      user.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png", content_type: "image/png"
      )
      user.update_columns(avatar_source: "upload")
      sign_in_via_form(user)
    end

    it "shows crop page with Cropper.js and controls" do
      visit crop_account_avatar_path
      dismiss_banner
      expect(page).to have_text(I18n.t("account.avatars.crop.title"))
      expect(page).to have_css("[data-controller='image-cropper']")
      # Cropper.js hides the original img and creates .cropper-container
      expect(page).to have_css(".cropper-container", wait: 5)
      expect(page).to have_css("[data-image-cropper-target='preview']")
      expect(page).to have_button(I18n.t("image_crop.save"))
      expect(page).to have_link(I18n.t("image_crop.skip"))
    end

    it "saves crop and redirects to profile" do
      visit crop_account_avatar_path
      dismiss_banner
      click_button I18n.t("image_crop.save")
      expect(page).to have_text(I18n.t("account.avatars.save_crop.success"), wait: 5)
    end

    it "skip returns to profile without saving" do
      visit crop_account_avatar_path
      dismiss_banner
      click_link I18n.t("image_crop.skip")
      expect(page).to have_current_path(edit_account_profile_path)
    end

    it "profile page links to crop and upload when avatar exists" do
      visit edit_account_profile_path
      dismiss_banner
      expect(page).to have_link(I18n.t("account.avatars.crop.link"))
      expect(page).to have_button(I18n.t("account.avatars.edit.upload_new"))
    end

    it "passes accessibility audit" do
      visit crop_account_avatar_path
      dismiss_banner
      # Wait for Cropper.js to initialize
      expect(page).to have_css(".cropper-container", wait: 5)
      axe_options = { runOnly: { type: "tag", values: [ "wcag2aa" ] } }
      expect(axe_clean?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations(axe_options).join("\n")}"
    end

    it "passes existing crop data to the controller" do
      Bullet.enable = false
      blob = user.avatar.blob
      blob.update!(
        metadata: blob.metadata.merge("crop" => { "x" => 10, "y" => 20, "w" => 100, "h" => 100 })
      )
      Bullet.enable = true
      visit crop_account_avatar_path
      dismiss_banner
      expect(page).to have_css("[data-image-cropper-existing-crop-value]")
      crop_json = find("[data-controller='image-cropper']")["data-image-cropper-existing-crop-value"]
      crop_data = JSON.parse(crop_json)
      expect(crop_data).to include("x" => 10, "y" => 20, "w" => 100, "h" => 100)
    end
  end
end
