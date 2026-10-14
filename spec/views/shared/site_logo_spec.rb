require "rails_helper"

# The lockup: mark plus wordmark, template-owned. It emits the two as siblings
# with no wrapper of its own, so the caller's link is the flex box and its
# `[&>svg]:h-*` utility reaches the mark directly (#1104).
RSpec.describe "shared/_site_logo.html.erb", type: :view do
  def roots_for(**locals)
    render partial: "shared/site_logo", locals: locals
    Nokogiri::HTML5.fragment(rendered).children.reject { |node| node.text? && node.text.strip.empty? }
  end

  around do |example|
    I18n.backend.store_translations(:en, application: { wordmark_tail: nil })
    example.run
  ensure
    I18n.backend.reload!
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

  context "when the fork's mark stands in for the name's first letter" do
    around do |example|
      I18n.backend.store_translations(:en, application: { wordmark_tail: "lassrooms" })
      example.run
    ensure
      I18n.backend.reload!
    end

    it "gives assistive tech the whole name once and hides the visible mark-plus-tail" do
      nodes = roots_for
      expect(nodes.first["class"]).to eq("sr-only")
      expect(nodes.first.text).to eq(I18n.t("application.name"))
      expect(nodes.last["aria-hidden"]).to eq("true")
      expect(nodes.last.at_css("svg")).to be_present
      expect(nodes.last.text.strip).to eq("lassrooms")
    end

    it "keeps the mark a direct child in the compact variant, with the name sr-only" do
      nodes = roots_for(name_class: "sr-only")
      expect(nodes.map(&:name)).to eq([ "span", "svg" ])
      expect(nodes.first.text).to eq(I18n.t("application.name"))
    end
  end
end
