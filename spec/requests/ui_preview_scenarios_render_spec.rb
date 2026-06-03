require "rails_helper"

# Safety net for the copyable-artifact catalog: every UI::* Lookbook preview
# scenario must render (HTTP 200) at its ViewComponent previews URL. Auto-discovers
# scenarios, so converting a preview to template-backed ERB stays covered without
# editing this file. (ViewComponent strips the `_preview` suffix from the URL path.)
RSpec.describe "UI component preview scenarios render", type: :request do
  ui_previews = ViewComponent::Preview.all.select { |p| p.name.to_s.start_with?("UI::") }

  ui_previews.each do |preview|
    preview.instance_methods(false).sort.each do |scenario|
      it "#{preview.preview_name}/#{scenario} renders" do
        get "/rails/view_components/#{preview.preview_name}/#{scenario}"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  it "discovered the UI previews" do
    expect(ui_previews.map(&:preview_name)).to include("ui/button_component", "ui/avatar_component")
  end
end
