# frozen_string_literal: true

require "rails_helper"

# Long trails collapse their middle. The ellipsis is decorative and the collapsed crumbs
# are omitted for EVERYONE — visual and AT alike — so the trail never claims a depth the
# reader cannot reach.
RSpec.describe UI::BreadcrumbComponent, type: :component do
  let(:trail) do
    [
      { label: "Home", href: "/" },
      { label: "Projects", href: "/projects" },
      { label: "Apollo", href: "/projects/1" },
      { label: "Tasks", href: "/projects/1/tasks" },
      { label: "Write the spec" }
    ]
  end

  def breadcrumb(**opts) = render_inline(described_class.new(items: trail, **opts))

  it "renders every crumb when under the limit" do
    breadcrumb(max_items: 5)

    expect(page).to have_css("li", count: 5)
    expect(page).to have_no_css("[data-slot=breadcrumb-ellipsis]")
  end

  it "renders every crumb when no limit is given" do
    breadcrumb

    expect(page).to have_css("li", count: 5)
  end

  it "collapses the middle when over the limit" do
    breadcrumb(max_items: 3)

    expect(page).to have_css("[data-slot=breadcrumb-ellipsis]", count: 1)
    expect(page).to have_link("Home")
    expect(page).to have_css("[aria-current=page]", text: "Write the spec")
  end

  it "drops the collapsed crumbs from the accessibility tree too, not just visually" do
    breadcrumb(max_items: 3)

    expect(page).to have_no_link("Apollo")
    expect(page.find("[data-slot=breadcrumb-ellipsis]")["aria-hidden"]).to eq("true")
  end

  it "always keeps the current page" do
    breadcrumb(max_items: 2)

    expect(page).to have_css("[aria-current=page]", text: "Write the spec")
  end

  it "rejects a limit too small to show a trail" do
    expect { breadcrumb(max_items: 1) }.to raise_error(ArgumentError, /max_items/)
  end

  # #778: gem-template parity — an href-less NON-last crumb (e.g. a policy-gated
  # middle item) renders as muted plain text, never a degenerate <a> with no href.
  it "renders an href-less middle item as a muted span, not an anchor" do
    render_inline(described_class.new(items: [
      { label: "Home", href: "/" },
      { label: "Restricted" },
      { label: "Write the spec" }
    ]))

    expect(page).to have_css("span.text-text-muted", text: "Restricted")
    expect(page).to have_no_css("a", text: "Restricted")
  end
end
