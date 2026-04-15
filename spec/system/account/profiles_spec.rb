require "rails_helper"

RSpec.describe "Account profile — identity picker", type: :system do
  let(:user) { create(:user) }
  let(:avatar_fixture) { Rails.root.join("spec/fixtures/files/avatar.png") }

  before do
    sign_in_via_form(user)
    visit edit_account_profile_path
  end

  describe "photo upload flow" do
    it "uploads, crops, and saves a new avatar" do
      open_identity_picker

      # Select Photo source — since no image exists yet, this opens the file picker
      select_identity_source("Photo")

      attach_identity_picker_file(avatar_fixture)

      # File select triggers crop view automatically
      wait_for_crop_view

      simulate_crop_adjustment

      click_button I18n.t("identity_picker.save_crop")

      # After save, modal returns to hub
      wait_for_hub_view

      # Server-side state: avatar and avatar_original both attached, source is upload
      user.reload
      expect(user.avatar).to be_attached
      expect(user.avatar_original).to be_attached
      expect(user.avatar_source).to eq("upload")
    end
  end

  describe "source switching" do
    it "switches to Initials with a custom color" do
      open_identity_picker

      select_identity_source("Initials")

      # Color picker panel should appear (User has has_color_picker: true)
      expect(page).to have_css("[data-identity-picker-target='colorPanel']:not([hidden])", wait: 2)

      set_identity_color_hue(120)  # green

      click_button I18n.t("identity_picker.save")

      # Modal closes on save & apply
      expect(page).to have_no_css("dialog[open]", wait: 3)

      user.reload
      expect(user.avatar_source).to eq("initials")
      expect(user.primary_color).to eq(120)
    end

    context "when user has a Gravatar" do
      before do
        user.update_columns(has_gravatar: true)
        visit edit_account_profile_path
      end

      it "switches to Gravatar" do
        open_identity_picker

        select_identity_source("Gravatar")

        # No color picker for Gravatar
        expect(page).to have_css("[data-identity-picker-target='colorPanel'][hidden]", visible: :hidden, wait: 2)

        click_button I18n.t("identity_picker.save")

        # Modal closes on save & apply
        expect(page).to have_no_css("dialog[open]", wait: 3)

        user.reload
        expect(user.avatar_source).to eq("gravatar")
      end
    end
  end

  describe "re-crop existing photo" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "loads avatar_original for re-crop and saves a new blob" do
      original_signed_id = user.avatar_original.blob.signed_id
      prior_avatar_key = user.avatar.blob.key

      open_identity_picker

      # Click the large photo preview to enter crop view
      find("button[data-identity-picker-target='photoPreview']").click

      wait_for_crop_view

      # Crop view image src should contain the avatar_original blob signed ID (not the avatar's)
      img_src = page.evaluate_script(
        "document.querySelector('.cropper-container img').getAttribute('src')"
      )
      expect(img_src).to include(original_signed_id)

      simulate_crop_adjustment

      click_button I18n.t("identity_picker.save_crop")

      wait_for_hub_view

      user.reload
      expect(user.avatar).to be_attached
      # New crop save creates a new avatar blob (different key than before)
      expect(user.avatar.blob.key).not_to eq(prior_avatar_key)
    end
  end

  describe "remove photo" do
    let(:user) do
      u = create(:user)
      u.avatar.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "avatar.png",
        content_type: "image/png"
      )
      u.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      u.update!(avatar_source: "upload")
      u
    end

    it "persists removal immediately (without clicking Save & apply)" do
      open_identity_picker

      # Enter crop view via photo preview
      find("button[data-identity-picker-target='photoPreview']").click
      wait_for_crop_view

      click_button I18n.t("identity_picker.remove_photo")

      # Returns to hub with Initials now selected
      wait_for_hub_view
      expect(page).to have_css("[data-source='initials'].border-interactive", wait: 2)

      # Server state persisted immediately — no Save & apply needed
      user.reload
      expect(user.avatar).not_to be_attached
      expect(user.avatar_original).not_to be_attached
      expect(user.avatar_source).to eq("initials")
    end
  end
end
