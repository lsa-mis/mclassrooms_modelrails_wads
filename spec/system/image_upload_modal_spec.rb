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
    it "opens the modal from the Change avatar link" do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text(I18n.t("image_upload.drop_zone"))
    end

    it "opens the modal from clicking the avatar" do
      find("button[aria-label='#{I18n.t('account.avatars.edit.change')}']").click
      expect(page).to have_css("dialog[open]")
    end

    it "closes the modal on X button click" do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("dialog[open]")
      find("button[aria-label='#{I18n.t('modals.close')}']").click
      expect(page).to have_no_css("dialog[open]")
    end
  end

  describe "auto-submit upload flow" do
    it "auto-uploads and shows crop UI in modal on file select" do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("dialog[open]")
      inject_file(filename: "avatar.png")

      # Modal stays open and shows crop UI (turbo stream replaces modal body)
      expect(page).to have_css("dialog[open]", wait: 5)
      expect(page).to have_text(I18n.t("image_crop.save"), wait: 5)
      expect(user.reload.avatar).to be_attached
    end
  end

  describe "client-side validation" do
    before do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("dialog[open]")
    end

    it "shows error for invalid file type" do
      page.execute_script(<<~JS)
        const input = document.querySelector('[data-image-upload-target="fileInput"]');
        const file = new File(['fake'], 'doc.pdf', { type: 'application/pdf' });
        const dt = new DataTransfer();
        dt.items.add(file);
        input.files = dt.files;
        input.dispatchEvent(new Event('change', { bubbles: true }));
      JS
      expect(page).to have_css("[data-image-upload-target='error']:not([hidden])", wait: 3)
      expect(page).to have_text(I18n.t("image_upload.errors.invalid_type"))
    end

    it "shows error for oversized file" do
      page.execute_script(<<~JS)
        const input = document.querySelector('[data-image-upload-target="fileInput"]');
        const content = new Uint8Array(6 * 1024 * 1024);
        const file = new File([content], 'huge.png', { type: 'image/png' });
        const dt = new DataTransfer();
        dt.items.add(file);
        input.files = dt.files;
        input.dispatchEvent(new Event('change', { bubbles: true }));
      JS
      expect(page).to have_css("[data-image-upload-target='error']:not([hidden])", wait: 3)
      expect(page).to have_text("too large")
    end
  end

  describe "accessibility" do
    it "upload zone is keyboard accessible with role=button" do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("[data-image-upload-target='uploadZone'][role='button'][tabindex='0']")
    end

    it "error display has role=alert" do
      click_button I18n.t("account.avatars.edit.change")
      expect(page).to have_css("[data-image-upload-target='error'][role='alert']", visible: :all)
    end

    it "avatar is clickable with aria-label" do
      expect(page).to have_css("button[aria-label='#{I18n.t('account.avatars.edit.change')}']")
    end
  end
end
