require "rails_helper"

RSpec.describe "Image cropper controller", type: :system do
  before do
    visit root_path
    # Dismiss the cookie consent banner if present
    page.execute_script(<<~JS)
      const banner = document.querySelector('[data-biscuit-target="banner"]');
      if (banner) banner.remove();
    JS
  end

  def inject_cropper(aspect_ratio: 1, max_width: 256, max_height: 256, max_file_size: 5)
    page.execute_script(<<~JS)
      const wrapper = document.createElement('div');
      wrapper.setAttribute('data-controller', 'image-cropper');
      wrapper.setAttribute('data-image-cropper-aspect-ratio-value', '#{aspect_ratio}');
      wrapper.setAttribute('data-image-cropper-max-width-value', '#{max_width}');
      wrapper.setAttribute('data-image-cropper-max-height-value', '#{max_height}');
      wrapper.setAttribute('data-image-cropper-max-file-size-value', '#{max_file_size}');
      wrapper.innerHTML = `
        <div data-image-cropper-target="uploadArea" id="upload-area">
          <label for="cropper-file-input">Choose file</label>
          <input type="file" id="cropper-file-input"
                 data-image-cropper-target="fileInput"
                 data-action="change->image-cropper#loadImage"
                 accept="image/png,image/jpeg,image/gif,image/webp">
        </div>
        <div data-image-cropper-target="cropArea" id="crop-area" style="display:none;" aria-live="polite" tabindex="-1">
          <img data-image-cropper-target="preview" id="crop-preview" style="max-width:100%;">
          <button data-action="click->image-cropper#cancel" id="crop-cancel">Cancel</button>
          <button data-action="click->image-cropper#crop" id="crop-save">Save</button>
        </div>
        <div id="error-output" role="alert"></div>
      `;

      // Listen for events and write them to the DOM for assertion
      wrapper.addEventListener('cropper:error', (e) => {
        document.getElementById('error-output').textContent = e.detail.message;
      });
      wrapper.addEventListener('cropper:complete', (e) => {
        const result = document.createElement('div');
        result.id = 'crop-result';
        result.textContent = 'blob-size:' + e.detail.blob.size + ',filename:' + e.detail.filename;
        document.body.appendChild(result);
      });

      document.body.appendChild(wrapper);
    JS
  end

  def create_test_image_data_url(size_bytes: 100)
    # Create a minimal valid PNG as a base64 data URL via canvas
    page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.createElement('canvas');
        canvas.width = 100;
        canvas.height = 100;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = 'red';
        ctx.fillRect(0, 0, 100, 100);
        return canvas.toDataURL('image/png');
      })()
    JS
  end

  def attach_file_via_js(filename: "test.png", type: "image/png", size_kb: 1)
    # Create a File object and set it on the input via JS.
    # For image/* types, generate a real PNG via canvas so the browser can decode it.
    # For non-image types or oversized files, use synthetic bytes (validation rejects before decode).
    page.execute_script(<<~JS)
      (async () => {
        const input = document.getElementById('cropper-file-input');
        let file;

        if ('#{type}'.startsWith('image/') && #{size_kb} < 1100) {
          // Generate a real decodable PNG from a canvas
          const canvas = document.createElement('canvas');
          canvas.width = 100;
          canvas.height = 100;
          const ctx = canvas.getContext('2d');
          ctx.fillStyle = 'red';
          ctx.fillRect(0, 0, 100, 100);
          const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
          file = new File([blob], '#{filename}', { type: '#{type}' });
        } else {
          // Synthetic bytes for validation-only tests (invalid type, oversized)
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

  describe "file validation" do
    it "rejects files with invalid MIME type" do
      inject_cropper
      attach_file_via_js(filename: "doc.pdf", type: "application/pdf")
      expect(page).to have_css("#error-output",
        text: "File type not supported")
    end

    it "rejects files exceeding max file size" do
      inject_cropper(max_file_size: 1)
      attach_file_via_js(filename: "huge.png", type: "image/png", size_kb: 1500)
      expect(page).to have_css("#error-output",
        text: "File is too large")
    end

    it "accepts valid image files and shows crop area" do
      inject_cropper
      attach_file_via_js(filename: "avatar.png", type: "image/png", size_kb: 10)
      expect(page).to have_css("#crop-area", visible: true, wait: 5)
      expect(page).to have_no_css("#upload-area", visible: true)
    end
  end

  describe "cropping" do
    before do
      inject_cropper
      attach_file_via_js(filename: "avatar.png", type: "image/png", size_kb: 10)
      expect(page).to have_css("#crop-area", visible: true, wait: 5)
    end

    it "dispatches cropper:complete with blob on save" do
      click_button "Save"
      expect(page).to have_css("#crop-result", wait: 5)
      result_text = find("#crop-result").text
      expect(result_text).to match(/blob-size:\d+/)
      expect(result_text).to include("filename:avatar.png")
    end

    it "returns to upload view on cancel" do
      click_button "Cancel"
      expect(page).to have_css("#upload-area", visible: true)
      expect(page).to have_no_css("#crop-area", visible: true)
    end
  end
end
