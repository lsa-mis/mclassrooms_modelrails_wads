require "rails_helper"

# The one pagy.series_nav call (#1169); `frame:` targets every link, built with
# tag.attributes so a frame name cannot escape the attribute.
RSpec.describe "shared/_pager", type: :view do
  # Not named `pagy`: Pagy::Method#pagy is in scope and would shadow the let.
  let(:pager) { Pagy::Offset.new(count: 100, page: 2, limit: 25, request: controller.request) }

  it "renders nothing when there is only one page" do
    render "shared/pager", pagy: Pagy::Offset.new(count: 5, limit: 25, request: controller.request)

    expect(rendered.strip).to be_empty
  end

  it "renders the pager with no frame target by default" do
    render "shared/pager", pagy: pager

    expect(rendered).to have_css("nav")
    expect(rendered).not_to include("data-turbo-frame")
  end

  it "gives every link the frame target when one is asked for" do
    render "shared/pager", pagy: pager, frame: "_top"

    # `a[href]`: the current page's anchor has no href and needs no frame.
    links = Capybara.string(rendered).all("nav a[href]")
    expect(links).not_to be_empty, "no pager links rendered, so this asserts nothing"
    links.each { |link| expect(link["data-turbo-frame"]).to eq("_top") }
  end

  it "escapes a frame name instead of letting it break the attribute" do
    render "shared/pager", pagy: pager, frame: '_top" onclick="alert(1)'

    expect(rendered).not_to include('onclick="alert(1)"')
  end
end
