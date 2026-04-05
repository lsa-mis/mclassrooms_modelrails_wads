require "rails_helper"

RSpec.describe "Modal system", type: :system do
  before do
    visit root_path
    # Dismiss the cookie consent banner if present so it doesn't intercept pointer events
    page.execute_script(<<~JS)
      const banner = document.querySelector('[data-biscuit-target="banner"]');
      if (banner) banner.remove();
    JS
    # Set a fast animation duration on the root element (where the controller reads it from)
    page.execute_script("document.documentElement.style.setProperty('--modal-animation-duration', '50ms')")
  end

  def inject_test_modal(options = {})
    open_value = options[:open] ? 'data-modal-open-value="true"' : ""
    page.execute_script(<<~JS)
      const wrapper = document.createElement('div');
      wrapper.setAttribute('data-controller', 'modal');
      #{options[:open] ? "wrapper.setAttribute('data-modal-open-value', 'true');" : ""}
      wrapper.innerHTML = `
        <button data-action="click->modal#open" id="test-modal-trigger">Open Modal</button>
        <dialog data-modal-target="dialog" id="test-modal"
                role="dialog" aria-modal="true" aria-labelledby="test-modal-title"
                class="bg-transparent backdrop:bg-transparent p-4">
          <div data-modal-target="panel"
               style="opacity:0; transform:scale(0.95); background:white; padding:24px; border-radius:8px; min-width:300px;">
            <h2 id="test-modal-title">Test Modal</h2>
            <p>Modal content for testing</p>
            <button data-action="click->modal#close" id="test-modal-close" aria-label="Close dialog">Close</button>
            <a href="#" id="test-modal-link">A focusable link</a>
          </div>
        </dialog>
      `;
      document.body.appendChild(wrapper);
    JS
  end

  describe "opening" do
    it "opens when trigger button is clicked" do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text("Test Modal")
    end

    it "opens on connect when open value is true" do
      inject_test_modal(open: true)
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text("Test Modal")
    end
  end

  describe "closing" do
    before do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
    end

    it "closes when close button is clicked" do
      click_button "Close"
      expect(page).to have_no_css("dialog[open]")
    end

    it "closes on Escape key" do
      page.driver.with_playwright_page do |pw_page|
        pw_page.keyboard.press("Escape")
      end
      expect(page).to have_no_css("dialog[open]")
    end

    it "closes on backdrop click" do
      page.driver.with_playwright_page do |pw_page|
        pw_page.mouse.click(5, 5)
      end
      expect(page).to have_no_css("dialog[open]")
    end

    it "returns focus to trigger button after close" do
      click_button "Close"
      expect(page).to have_no_css("dialog[open]")
      focused_id = page.evaluate_script("document.activeElement?.id")
      expect(focused_id).to eq("test-modal-trigger")
    end
  end

  describe "accessibility" do
    before do
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")
    end

    it "has role=dialog" do
      expect(page).to have_css("dialog[role='dialog']")
    end

    it "has aria-modal=true" do
      expect(page).to have_css("dialog[aria-modal='true']")
    end

    it "has aria-labelledby pointing to title" do
      expect(page).to have_css("dialog[aria-labelledby='test-modal-title']")
      expect(page).to have_css("h2#test-modal-title", text: "Test Modal")
    end

    it "close button is keyboard accessible" do
      close_btn = find("#test-modal-close")
      close_btn.send_keys(:enter)
      expect(page).to have_no_css("dialog[open]")
    end
  end

  describe "reduced motion" do
    it "skips animation when prefers-reduced-motion is set" do
      page.driver.with_playwright_page do |pw_page|
        pw_page.emulate_media(reducedMotion: "reduce")
      end
      inject_test_modal
      click_button "Open Modal"
      expect(page).to have_css("dialog[open]")

      # Panel should be immediately visible (opacity 1, no transition)
      panel_opacity = page.evaluate_script(
        'document.querySelector("[data-modal-target=\\"panel\\"]")?.style.opacity'
      )
      expect(panel_opacity).to eq("1")
    end
  end
end
