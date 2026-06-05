# frozen_string_literal: true

require "rails_helper"

# Dev-only light/dark toggle on the component preview host (component_preview
# layout + preview_theme_controller). Verifies the toggle flips `.dark` on <html>
# so reviewers can check components in both themes from Lookbook / the preview URL.
RSpec.describe "Component preview theme toggle", type: :system do
  it "flips the .dark class on the preview host" do
    visit "/rails/view_components/ui/button_component/primary"

    expect(page).to have_no_css("html.dark")

    find("[data-action~='click->preview-theme#toggle']").click
    expect(page).to have_css("html.dark")

    find("[data-action~='click->preview-theme#toggle']").click
    expect(page).to have_no_css("html.dark")
  end
end
