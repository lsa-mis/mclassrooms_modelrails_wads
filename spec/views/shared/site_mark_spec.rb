require "rails_helper"

# The brand mark is the fork-owned third of brand (words: brand.en.yml,
# colors: _brand.css, mark: this partial). A fork replaces the file wholesale,
# so its contract with the template's lockup has to be asserted here, not just
# narrated in a guide that drifted once already (#1104).
RSpec.describe "shared/_site_mark.html.erb", type: :view do
  let(:fragment) do
    render partial: "shared/site_mark"
    Nokogiri::HTML5.fragment(rendered)
  end
  let(:roots) { fragment.children.reject { |node| node.text? && node.text.strip.empty? } }
  let(:svg) { roots.first }

  it "is exactly one <svg> and nothing else — the lockup owns layout, the mark owns paint" do
    expect(roots.map(&:name)).to eq([ "svg" ])
  end

  it "is decorative: the brand name next to it is what assistive tech reads" do
    expect(svg["aria-hidden"]).to eq("true")
  end

  it "inherits its color, so text-interactive re-lights it under .dark" do
    expect(svg["fill"]).to eq("currentColor")
  end

  it "carries a viewBox and no width, height, or class, so the caller can size it" do
    expect(svg["viewBox"]).to be_present
    expect(svg.attributes.keys).not_to include("width", "height", "class")
  end
end
