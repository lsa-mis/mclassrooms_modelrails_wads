require "rails_helper"

RSpec.describe "Image upload modal", type: :system do
  before do
    visit root_path
    # Dismiss the cookie consent banner if present
    page.execute_script(<<~JS)
      const banner = document.querySelector('[data-biscuit-target="banner"]');
      if (banner) banner.remove();
    JS
    page.execute_script("document.documentElement.style.setProperty('--modal-animation-duration', '50ms')")
  end

  def inject_upload_modal(crop: false, aspect_ratio: 1, max_file_size: 5)
    crop_controller_attrs = if crop
      <<~ATTRS
        data-controller="image-cropper"
        data-image-cropper-aspect-ratio-value="#{aspect_ratio}"
        data-image-cropper-max-width-value="512"
        data-image-cropper-max-height-value="512"
        data-image-cropper-max-file-size-value="#{max_file_size}"
        data-action="cropper:complete->image-upload#handleCropComplete cropper:error->image-upload#handleCropError"
        data-error-message-invalid-type="File type not supported. Please use PNG, JPG, GIF, or WebP."
        data-error-message-file-too-large="File is too large. Maximum size is #{max_file_size}MB."
        data-error-message-cropper-load-failed="Image editor could not load. Your image will be uploaded without cropping."
      ATTRS
    else
      ""
    end

    upload_area_open = crop ? '<div data-image-cropper-target="uploadArea">' : ""
    upload_area_close = crop ? "</div>" : ""

    file_input_action = if crop
      'data-image-cropper-target="fileInput" data-action="change->image-cropper#loadImage"'
    else
      'data-action="change->image-upload#submit"'
    end

    crop_area_html = if crop
      <<~HTML
        <div data-image-cropper-target="cropArea" id="crop-area"
             style="display:none;" aria-live="polite" tabindex="-1">
          <p>Drag to reposition. Scroll to zoom.</p>
          <img data-image-cropper-target="preview" alt="Crop image" style="max-width:100%;">
          <button data-action="click->image-cropper#cancel" id="crop-cancel"
                  style="min-height:44px;min-width:44px;">Cancel</button>
          <button data-action="click->image-cropper#crop" id="crop-save"
                  style="min-height:44px;min-width:44px;">Save</button>
        </div>
      HTML
    else
      ""
    end

    js = <<~JS
      const wrapper = document.createElement('div');
      wrapper.setAttribute('data-controller', 'modal');
      wrapper.innerHTML = `
        <button data-action="click->modal#open" id="upload-trigger">Upload Image</button>
        <dialog data-modal-target="dialog" id="upload-modal"
                role="dialog" aria-modal="true" aria-labelledby="upload-modal-title"
                class="bg-transparent backdrop:bg-transparent p-4">
          <div data-modal-target="panel"
               style="opacity:0; transform:scale(0.95); background:white; padding:24px; border-radius:8px; min-width:400px;">
            <h2 id="upload-modal-title">Upload Image</h2>
            <button data-action="click->modal#close" aria-label="Close dialog">X</button>

            <div data-controller="image-upload"
                 data-image-upload-crop-value="CROP_VALUE">

              <div id="error-display"
                   data-image-upload-target="errorMessage"
                   role="alert" hidden></div>

              <form data-image-upload-target="form" action="/test-upload" method="post"
                    enctype="multipart/form-data">
                <div CROP_CONTROLLER_ATTRS
                     data-image-upload-target="dropZone">
                  UPLOAD_AREA_OPEN
                  <label for="upload-file-input">
                    Click to upload or drag and drop
                    <input type="file" id="upload-file-input"
                           accept="image/png,image/jpeg,image/gif,image/webp"
                           class="sr-only"
                           data-image-upload-target="fileInput"
                           FILE_INPUT_ACTION>
                  </label>
                  UPLOAD_AREA_CLOSE
                  CROP_AREA_HTML
                </div>
              </form>
            </div>
          </div>
        </dialog>
      `;
      document.body.appendChild(wrapper);
    JS
      .gsub("CROP_VALUE", crop.to_s)
      .gsub("CROP_CONTROLLER_ATTRS", crop_controller_attrs.strip.gsub("\n", " "))
      .gsub("UPLOAD_AREA_OPEN", upload_area_open)
      .gsub("UPLOAD_AREA_CLOSE", upload_area_close)
      .gsub("FILE_INPUT_ACTION", file_input_action)
      .gsub("CROP_AREA_HTML", crop_area_html.strip.gsub("\n", " ").gsub('"', '\\"'))

    page.execute_script(js)
  end

  def attach_file_via_js(input_id: "upload-file-input", filename: "test.png", type: "image/png", size_kb: 1)
    page.execute_script(<<~JS)
      (async () => {
        const input = document.getElementById('#{input_id}');
        let file;

        if ('#{type}'.startsWith('image/') && #{size_kb} < 1100) {
          const canvas = document.createElement('canvas');
          canvas.width = 100;
          canvas.height = 100;
          const ctx = canvas.getContext('2d');
          ctx.fillStyle = 'red';
          ctx.fillRect(0, 0, 100, 100);
          const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
          file = new File([blob], '#{filename}', { type: '#{type}' });
        } else {
          const content = new Uint8Array(#{size_kb * 1024});
          file = new File([content], '#{filename}', { type: '#{type}' });
        }

        const dt = new DataTransfer();
        dt.items.add(file);
        input.files = dt.files;
        input.dispatchEvent(new Event('change', { bubbles: true }));
      })();
    JS
  end

  describe "modal interaction" do
    it "opens the upload modal when trigger is clicked" do
      inject_upload_modal
      click_button "Upload Image"
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text("Upload Image")
      expect(page).to have_text("Click to upload or drag and drop")
    end

    it "closes the modal on close button click" do
      inject_upload_modal
      click_button "Upload Image"
      expect(page).to have_css("dialog[open]")
      find("button[aria-label='Close dialog']").click
      expect(page).to have_no_css("dialog[open]")
    end
  end

  describe "without crop" do
    it "has a file input that triggers form submission on change" do
      inject_upload_modal(crop: false)
      click_button "Upload Image"
      expect(page).to have_css("dialog[open]")
      expect(page).to have_css("input[type='file']", visible: :all)
    end
  end

  describe "with crop" do
    it "shows crop area when a valid file is selected" do
      inject_upload_modal(crop: true)
      click_button "Upload Image"
      expect(page).to have_css("dialog[open]")
      attach_file_via_js(filename: "avatar.png", type: "image/png", size_kb: 10)
      expect(page).to have_css("#crop-area", visible: true, wait: 5)
    end

    it "returns to upload view when cancel is clicked" do
      inject_upload_modal(crop: true)
      click_button "Upload Image"
      attach_file_via_js(filename: "avatar.png", type: "image/png", size_kb: 10)
      expect(page).to have_css("#crop-area", visible: true, wait: 5)
      click_button "Cancel"
      expect(page).to have_no_css("#crop-area", visible: true)
    end

    it "shows error for invalid file type" do
      inject_upload_modal(crop: true)
      click_button "Upload Image"
      attach_file_via_js(filename: "doc.pdf", type: "application/pdf")
      expect(page).to have_css("#error-display:not([hidden])",
        text: "File type not supported", wait: 5)
    end

    it "shows error for oversized file" do
      inject_upload_modal(crop: true, max_file_size: 1)
      click_button "Upload Image"
      attach_file_via_js(filename: "huge.png", type: "image/png", size_kb: 1500)
      expect(page).to have_css("#error-display:not([hidden])",
        text: "File is too large", wait: 5)
    end
  end

  describe "accessibility" do
    it "upload zone label is keyboard accessible" do
      inject_upload_modal
      click_button "Upload Image"
      expect(page).to have_css("label[for='upload-file-input']")
    end

    it "error display has role=alert" do
      inject_upload_modal
      click_button "Upload Image"
      expect(page).to have_css("#error-display[role='alert']", visible: :all)
    end

    it "crop area has aria-live=polite when crop is enabled" do
      inject_upload_modal(crop: true)
      click_button "Upload Image"
      expect(page).to have_css("#crop-area[aria-live='polite']", visible: :all)
    end

    it "crop area has tabindex for focus management" do
      inject_upload_modal(crop: true)
      click_button "Upload Image"
      expect(page).to have_css("#crop-area[tabindex='-1']", visible: :all)
    end

    it "crop buttons meet minimum touch target size" do
      inject_upload_modal(crop: true)
      click_button "Upload Image"
      expect(page).to have_css("#crop-cancel[style*='min-height:44px']", visible: :all)
      expect(page).to have_css("#crop-save[style*='min-height:44px']", visible: :all)
    end
  end
end
