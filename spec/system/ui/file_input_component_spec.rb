# frozen_string_literal: true

require "rails_helper"

# Preview-host proof for the file_input show_selection mode: the render harness
# only sees the server-rendered Stimulus wiring — the pills, the list un-hiding,
# and the sr-only live-region announcement are all produced at runtime by the
# `file-input` controller, so this spec proves them in a real browser.
#
# Stable selectors: the component's own load-bearing data-file-input-target
# hooks (the Stimulus contract), not selectors invented for the test.
RSpec.describe "File input component selection display", type: :system do
  # `let`, not constants (#607/#608) — see spec/code_smells/no_object_level_spec_constants_spec.rb.
  let(:preview)         { "/rails/view_components/ui/file_input_component/show_selection" }
  let(:input_selector)  { "input[data-file-input-target='input']" }
  let(:list_selector)   { "ul[data-file-input-target='list']" }
  let(:status_selector) { "span[data-file-input-target='status']" }
  let(:avatar_fixture)  { Rails.root.join("spec/fixtures/files/avatar.png").to_s }
  let(:bmp_fixture)     { Rails.root.join("spec/fixtures/files/unfuzzed.bmp").to_s }

  # The status region is sr-only, so its text is read with `visible: :all` +
  # `text(:all)` (Capybara treats clipped-but-rendered elements as hidden).
  def status_text
    find(status_selector, visible: :all).text(:all).strip
  end

  describe "AAA accessibility" do
    it "passes AAA in both themes" do
      visit preview
      expect(page).to have_css("[data-controller='file-input']")

      scope = [ "[data-controller='file-input']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  describe "selection display (file-input#update)" do
    it "shows one pill per selected file, un-hides the list, and announces the selection" do
      visit preview
      expect(page).to have_css(input_selector)
      expect(page).to have_css("#{list_selector}[hidden]", visible: :all)

      attach_file("demo_gallery[]", [ avatar_fixture, bmp_fixture ])

      within(list_selector) do
        expect(page).to have_css("li", count: 2)
        expect(page).to have_css("li", exact_text: "avatar.png")
        expect(page).to have_css("li", exact_text: "unfuzzed.bmp")
      end
      expect(page).to have_no_css("#{list_selector}[hidden]", visible: :all)
      expect(status_text).to eq("2 files selected: avatar.png, unfuzzed.bmp")
    end

    it "replaces the pills and announces the singular string on re-selection" do
      visit preview
      expect(page).to have_css(input_selector)

      attach_file("demo_gallery[]", [ avatar_fixture, bmp_fixture ])
      expect(page).to have_css("#{list_selector} li", count: 2)

      attach_file("demo_gallery[]", avatar_fixture)

      within(list_selector) do
        expect(page).to have_css("li", count: 1)
        expect(page).to have_css("li", exact_text: "avatar.png")
      end
      expect(status_text).to eq("1 file selected: avatar.png")
    end
  end
end
