require "rails_helper"

# The text-level guard (spec/code_smells/lists_carry_the_list_role_spec.rb) proves
# the source says `role="list"`. This proves it reaches the DOM — and for the two
# components that splat a caller's `**html_attrs` onto the list element, that a
# caller's override replaces the default rather than emitting a second `role`
# attribute.
#
# One file rather than seven: the assertion is the same contract in each case, and
# five of these components have no spec of their own to grow.
RSpec.describe "Vendored components restore the list role", type: :component do
  # `content_tag` de-duplicates neither `:role` against `"role"` nor the reverse —
  # it emits BOTH and the winner is browser-dependent. A CSS selector cannot see
  # that (Nokogiri collapses it), so the count runs on the element's own raw tag.
  def role_count(tag)
    rendered_content[/<#{tag}[^>]*>/].scan(/\srole=/).length
  end

  it "renders role=list on the timeline" do
    render_inline(UI::TimelineComponent.new)

    expect(page).to have_css("ol[role=list]", visible: :all)
  end

  it "renders role=list on the stepper" do
    render_inline(UI::StepperComponent.new(steps: [ { label: "One", status: :current } ]))

    expect(page).to have_css("ol[role=list]", visible: :all)
  end

  it "renders role=list on the breadcrumb" do
    render_inline(UI::BreadcrumbComponent.new(items: [ { label: "Home", href: "/" }, { label: "Here" } ]))

    expect(page).to have_css("ol[role=list]", visible: :all)
  end

  it "renders role=list on the navigation menu" do
    render_inline(UI::NavigationMenuComponent.new) { |m| m.with_item(label: "Docs", href: "/docs") }

    expect(page).to have_css("ul[role=list]", visible: :all)
  end

  it "renders role=list on a mega menu column" do
    render_inline(UI::MegaMenuComponent.new(label: "Products")) do |m|
      m.with_column(heading: "Platform", items: [ { title: "Overview", href: "#" } ])
    end

    expect(page).to have_css("ul[role=list]", visible: :all)
  end

  it "renders role=list on a footer link column" do
    render_inline(UI::FooterComponent.new(columns: [ { title: "Product", links: [ { label: "Pricing", href: "/p" } ] } ]))

    expect(page).to have_css("ul[role=list]", visible: :all)
  end

  it "renders role=list on the file input's selection list" do
    render_inline(UI::FileInputComponent.new(show_selection: true))

    expect(page).to have_css("ul[role=list]", visible: :all)
  end

  # --- the override contract, where a caller can reach the element -------------

  it "lets a caller's role replace the timeline's without duplicating it" do
    caller_attrs = { "role" => "presentation" }
    render_inline(UI::TimelineComponent.new(**caller_attrs))

    expect(role_count("ol")).to eq(1), rendered_content
    expect(rendered_content).to include('role="presentation"')
  end

  it "lets a caller's role replace the stepper's without duplicating it" do
    caller_attrs = { "role" => "presentation" }
    render_inline(UI::StepperComponent.new(steps: [ { label: "One" } ], **caller_attrs))

    expect(role_count("ol")).to eq(1), rendered_content
  end

  # The same trap applied to the stepper's default aria-label, which a caller
  # could previously only duplicate rather than replace.
  it "lets a caller replace the stepper's aria-label without duplicating it" do
    caller_attrs = { "aria-label" => "Checkout" }
    render_inline(UI::StepperComponent.new(steps: [ { label: "One" } ], **caller_attrs))

    expect(rendered_content[/<ol[^>]*>/].scan(/\saria-label=/).length).to eq(1)
    expect(rendered_content).to include('aria-label="Checkout"')
  end
end
