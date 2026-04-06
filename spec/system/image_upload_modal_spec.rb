require "rails_helper"

RSpec.describe "Image upload modal", type: :system do
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

  def inject_file(filename: "test.png")
    page.execute_script(<<~JS)
      (async () => {
        const input = document.querySelector('[data-image-upload-target="fileInput"]');
        const canvas = document.createElement('canvas');
        canvas.width = 200; canvas.height = 200;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = 'blue'; ctx.fillRect(0, 0, 200, 200);
        const blob = await new Promise(r => canvas.toBlob(r, 'image/png'));
        const file = new File([blob], '#{filename}', { type: 'image/png' });
        const dt = new DataTransfer();
        dt.items.add(file);
        input.files = dt.files;
        input.dispatchEvent(new Event('change', { bubbles: true }));
      })();
    JS
  end

  before do
    sign_in_via_form(user)
    visit edit_account_profile_path
    dismiss_banner
  end

  describe "opening and closing" do
    it "opens the modal from the profile page" do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text(I18n.t("image_upload.drop_zone"))
    end

    it "closes the modal on X button click" do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("dialog[open]")
      find("button[aria-label='#{I18n.t('modals.close')}']").click
      expect(page).to have_no_css("dialog[open]")
    end
  end

  describe "file selection" do
    before do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("dialog[open]")
    end

    it "shows preview after file selection" do
      inject_file
      expect(page).to have_css("[data-image-upload-target='preview']:not([hidden])", wait: 3)
    end

    it "shows upload button after file selection" do
      inject_file
      expect(page).to have_button(I18n.t("image_upload.upload"), wait: 3)
    end

    it "shows choose different button that re-opens file picker" do
      inject_file
      expect(page).to have_button(I18n.t("image_upload.choose_different"), wait: 3)
    end
  end

  describe "uploading" do
    it "uploads the avatar and shows success message" do
      click_button I18n.t("account.avatars.edit.change")
      inject_file(filename: "avatar.png")
      expect(page).to have_button(I18n.t("image_upload.upload"), wait: 3)
      click_button I18n.t("image_upload.upload")

      expect(page).to have_text(I18n.t("account.avatars.update.success"), wait: 5)
      expect(user.reload.avatar).to be_attached
      expect(user.avatar_source).to eq("upload")
    end
  end

  describe "accessibility" do
    it "upload zone is keyboard accessible with role=button" do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("[data-image-upload-target='uploadZone'][role='button'][tabindex='0']")
    end
  end
end
