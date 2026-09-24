require "rails_helper"

# Two surfaces rendered `pagy.series_nav` with different arguments: the shared
# pagination partial plain, and the operations ledger with an `anchor_string`
# so its links escape the Turbo frame. One call, two spellings, and the ledger's
# was a hand-written attribute string (#1169).
#
# `frame:` is the seam. Absent, the pager behaves as it always did; set, every
# link carries that frame target — built with `tag.attributes`, not
# interpolated, so a frame name can never break out of the attribute.
RSpec.describe "shared/_pager", type: :view do
  # series_nav builds hrefs off the request, so it needs the real one the view
  # spec already has rather than a stand-in hash.
  #
  # NOT named `pagy`: Pagy::Method#pagy is in scope here and takes 1..2
  # arguments, so `pagy: pagy` calls the helper with none rather than reading
  # the let, and fails with a wrong-number-of-arguments error pointing at the
  # render line.
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

    # `a[href]`: pagy marks the current page with an anchor that has no href,
    # which is correct — it navigates nowhere and needs no frame target.
    links = Capybara.string(rendered).all("nav a[href]")
    expect(links).not_to be_empty, "no pager links rendered, so this asserts nothing"
    links.each { |link| expect(link["data-turbo-frame"]).to eq("_top") }
  end

  # Built through tag.attributes rather than interpolated into a string, so a
  # frame name carrying a quote cannot close the attribute and add its own.
  it "escapes a frame name instead of letting it break the attribute" do
    render "shared/pager", pagy: pager, frame: '_top" onclick="alert(1)'

    expect(rendered).not_to include('onclick="alert(1)"')
  end
end
