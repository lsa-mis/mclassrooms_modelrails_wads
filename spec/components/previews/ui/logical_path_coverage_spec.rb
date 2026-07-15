# frozen_string_literal: true

require "rails_helper"

# Mirror of the gem's taxonomy guard: every vendored app preview must declare a
# @logical_path in one of the 8 canonical sections. (toaster/wysiwyg are gem-only —
# superseded in this app — so they are absent here by design.)
# Tag form is UNQUOTED: `# @logical_path Forms & Inputs`.
RSpec.describe "Lookbook preview logical_path coverage" do
  preview_root = Rails.root.join("spec/components/previews/ui")

  sections = [
    "Forms & Inputs", "Actions", "Overlays", "Navigation",
    "Feedback & Status", "Data Display", "Media", "Layout"
  ]

  expected = {
    "input" => "Forms & Inputs", "textarea" => "Forms & Inputs", "select" => "Forms & Inputs",
    "checkbox" => "Forms & Inputs", "radio_group" => "Forms & Inputs", "switch" => "Forms & Inputs",
    "toggle" => "Forms & Inputs", "toggle_group" => "Forms & Inputs", "range" => "Forms & Inputs",
    "number_input" => "Forms & Inputs", "search_input" => "Forms & Inputs",
    "file_input" => "Forms & Inputs", "input_otp" => "Forms & Inputs", "combobox" => "Forms & Inputs",
    "date_picker" => "Forms & Inputs", "timepicker" => "Forms & Inputs", "calendar" => "Forms & Inputs",
    "rating_input" => "Forms & Inputs", "floating_label" => "Forms & Inputs", "label" => "Forms & Inputs",
    "form_field" => "Forms & Inputs", "form_draft" => "Forms & Inputs",
    "button" => "Actions", "button_group" => "Actions", "speed_dial" => "Actions", "command" => "Actions",
    "dialog" => "Overlays", "alert_dialog" => "Overlays", "drawer" => "Overlays", "sheet" => "Overlays",
    "popover" => "Overlays", "tooltip" => "Overlays", "hover_card" => "Overlays",
    "dropdown_menu" => "Overlays", "context_menu" => "Overlays", "menubar" => "Overlays",
    "navbar" => "Navigation", "sidebar" => "Navigation", "breadcrumb" => "Navigation",
    "tabs" => "Navigation", "bottom_nav" => "Navigation", "mega_menu" => "Navigation",
    "navigation_menu" => "Navigation", "footer" => "Navigation",
    "alert" => "Feedback & Status", "banner" => "Feedback & Status", "badge" => "Feedback & Status",
    "progress" => "Feedback & Status", "spinner" => "Feedback & Status", "skeleton" => "Feedback & Status",
    "indicator" => "Feedback & Status", "stepper" => "Feedback & Status",
    "card" => "Data Display", "list_group" => "Data Display", "data_table" => "Data Display",
    "timeline" => "Data Display", "accordion" => "Data Display", "collapsible" => "Data Display",
    "chat_bubble" => "Data Display", "avatar" => "Data Display", "kbd" => "Data Display",
    "rating" => "Data Display", "chart" => "Data Display",
    "image" => "Media", "picture" => "Media", "figure" => "Media", "gallery" => "Media",
    "audio" => "Media", "video" => "Media", "embed" => "Media", "iframe" => "Media",
    "carousel" => "Media", "qr_code" => "Media", "device_mockup" => "Media",
    "map_area" => "Media", "aspect_ratio" => "Media",
    "separator" => "Layout", "scroll_area" => "Layout", "resizable" => "Layout"
  }

  components = Dir.glob(preview_root.join("*_component_preview.rb"))
    .map { |p| File.basename(p, "_component_preview.rb") }

  it "covers every preview in the expected taxonomy map" do
    expect(components - expected.keys).to be_empty
    expect(expected.keys - components).to be_empty
  end

  components.each do |component|
    it "#{component} declares its expected @logical_path" do
      src = File.read(preview_root.join("#{component}_component_preview.rb"))
      actual = src[/^\s*#\s*@logical_path\s+(.+?)\s*$/, 1]
      expect(actual).not_to be_nil, "#{component}: missing @logical_path tag"
      expect(sections).to include(actual)
      expect(actual).to eq(expected[component])
    end
  end
end
