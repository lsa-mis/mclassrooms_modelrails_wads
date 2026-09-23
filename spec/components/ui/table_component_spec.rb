# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::TableComponent, type: :component do
  def render_table(**opts, &block)
    render_inline(described_class.new(caption: "All widgets", **opts)) do |t|
      t.with_header { "<th scope=\"col\">Name</th>".html_safe }
      t.with_body { "<tr><td>Widget</td></tr>".html_safe }
      block&.call(t)
    end
  end

  it "renders a table with a visually hidden caption by default" do
    render_table
    expect(page).to have_css("table caption.sr-only", text: "All widgets")
    expect(page).to have_css("thead tr th[scope=col]", text: "Name")
    expect(page).to have_css("tbody tr td", text: "Widget")
  end

  it "shows the caption when asked" do
    render_table(caption_visible: true)
    expect(page).to have_css("table caption:not(.sr-only)", text: "All widgets")
  end

  it "requires a caption — the table's accessible name is not optional" do
    expect { render_inline(described_class.new(caption: "")) }.to raise_error(ArgumentError, /caption/)
  end

  it "exposes the size on the wrapper and rejects unknown sizes" do
    render_table(size: :compact)
    expect(page).to have_css("div[data-size=compact] table")
    expect { described_class.new(caption: "x", size: :huge) }.to raise_error(ArgumentError, /size/)
  end

  it "renders the toolbar slot before the table, inside the bordered wrapper" do
    render_table { |t| t.with_toolbar { "Summary" } }
    expect(page).to have_css("div.rounded-lg > div[data-slot=toolbar] + table", visible: :all)
    expect(page).to have_css("div.rounded-lg > div[data-slot=toolbar]", text: "Summary")
  end

  it "renders the footer slot after the table, inside the bordered wrapper" do
    render_table { |t| t.with_footer { "Showing 1–1 of 1" } }
    expect(page).to have_css("div.rounded-lg > table + div[data-slot=footer]", text: "Showing 1–1 of 1")
  end

  it "keeps the header cell classes on the shared constant so sortable headers match plain ones" do
    expect(UI::TableComponent::TH).to include("h-11")
    expect(UI::TableComponent::TH).to include("text-left")
  end

  it "merges a caller-supplied data: hash instead of letting it clobber data-size" do
    render_table(data: { controller: "x" })
    expect(page).to have_css("div[data-size=default][data-controller=x]")
  end

  # scroll: :horizontal wraps only the <table> in the scroll region, so the
  # toolbar and footer stay pinned at phone width instead of scrolling off
  # with the columns. The region is a named, focusable tab stop (the
  # ScrollArea contract), named distinctly from the caption so a screen
  # reader does not hear the same words twice.
  it "scrolls only the table when asked, leaving toolbar and footer pinned" do
    render_table(scroll: :horizontal) do |t|
      t.with_toolbar { "Summary" }
      t.with_footer { "Showing 1–1 of 1" }
    end
    region = page.find("div[role=region][tabindex='0']")
    expect(region[:"aria-label"]).to eq(I18n.t("modelrails_ui.table.scroll_region", name: "All widgets"))
    expect(region[:class]).to include("overflow-x-auto").and include("focus-ring")
    expect(region).to have_css("table")
    expect(page).to have_css("div.rounded-lg > div[data-slot=toolbar] + div[role=region] + div[data-slot=footer]", visible: :all)
  end

  it "renders no scroll region by default" do
    render_table
    expect(page).to have_no_css("[role=region]")
    expect(page).to have_css("div[data-size] > table")
  end

  # The port-time decision was to follow list_group onto bg-surface. Overturned in
  # modelrails_ui #210: bg-surface IS the page, so both were painting a container
  # the colour of the ground beneath it — the old wording here ("not the page's")
  # had it backwards. The card family agrees on bg-surface-raised, and this app's
  # <body> moved to bg-surface to match.
  it "is a filled card on the raised surface, lifting off the page" do
    expect(UI::TableComponent::WRAPPER).to include("bg-surface-raised")
  end
end
