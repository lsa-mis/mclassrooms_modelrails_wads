# frozen_string_literal: true

require "rails_helper"

# WCAG 2.4.3 (#424): a Turbo Drive visit replaces the document under the
# user — without a focus move, a keyboard/AT user's focus and virtual cursor
# stay parked on the OLD page's position while new content renders around
# them. Every layout ships `#main-content` with tabindex="-1" as the landing
# target; navigation_focus.js is the global handler that actually lands
# there. Guarded here end-to-end because the failure is invisible to any
# markup-level check.
RSpec.describe "Post-navigation focus management", type: :system do
  it "moves focus to #main-content after a Turbo Drive navigation" do
    visit "/"
    click_link I18n.t("footer.about") # destination has no autofocused field

    expect(page).to have_css("#main-content")
    expect(page.evaluate_script("document.activeElement && document.activeElement.id")).to eq("main-content")
  end

  it "leaves the browser's default focus alone on initial page load" do
    visit "/"

    expect(page).to have_css("#main-content")
    expect(page.evaluate_script("document.activeElement === document.body")).to be(true)
  end

  it "does not fight an autofocused field on the destination page" do
    # The login page's email field autofocuses; the handler must yield to it
    # rather than yank focus onto the landmark.
    visit "/"
    # Fork's landing renders several sign-in links (header + hero); any of
    # them is a Turbo Drive visit, so the first is fine.
    click_link I18n.t("navigation.sign_in"), match: :first

    focused_tag = page.evaluate_script("document.activeElement && document.activeElement.tagName")
    expect(%w[INPUT MAIN]).to include(focused_tag),
      "expected focus on the landmark or an autofocused field, got #{focused_tag.inspect}"
  end
end
