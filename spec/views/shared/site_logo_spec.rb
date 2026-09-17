require "rails_helper"

# The lockup: mark plus wordmark, template-owned. It emits the two as siblings
# with no wrapper of its own, so the caller's link is the flex box and its
# `[&>svg]:h-*` utility reaches the mark directly (#1104).
RSpec.describe "shared/_site_logo.html.erb", type: :view do
  def roots_for(**locals)
    render partial: "shared/site_logo", locals: locals
    Nokogiri::HTML5.fragment(rendered).children.reject { |node| node.text? && node.text.strip.empty? }
  end

  it "renders the mark and the name as siblings, nothing wrapping them" do
    expect(roots_for.map(&:name)).to eq([ "svg", "span" ])
  end

  it "names the product from the fork-owned brand locale" do
    expect(roots_for.last.text).to eq(I18n.t("application.name"))
  end

  it "lets a caller keep the name for assistive tech only" do
    expect(roots_for(name_class: "sr-only").last["class"]).to eq("sr-only")
  end

  it "has no size or color knobs — the caller's link owns both" do
    expect { roots_for(size: :small) }.to raise_error(ActionView::Template::Error, /size/)
  end
end
