# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::SearchInputComponent, type: :component do
  it "renders a search input" do
    render_inline(described_class.new(name: "q"))

    expect(page).to have_css("input[type='search']")
  end

  # A search input needs an accessible name. We supply one via aria-label with an
  # i18n default so the control is never unlabelled (placeholder is only a hint).
  it "has an accessible name via aria-label" do
    render_inline(described_class.new(name: "q"))

    label = page.find("input[type='search']")["aria-label"]

    expect(label).not_to be_nil
    expect(label.to_s).not_to be_empty
  end

  it "allows the aria-label to be overridden" do
    render_inline(described_class.new(name: "q", label: "Search products"))

    expect(page).to have_css("input[type='search'][aria-label='Search products']")
  end

  # AAA semantic tokens (the design-token guarantee), not raw Tailwind:
  it "renders with AAA semantic tokens" do
    render_inline(described_class.new(name: "q"))

    expect(page).to have_css("input.border-border-strong")
    expect(page).to have_css('input.focus-visible\\:ring-interactive-focus')
  end

  # WCAG 2.5.5 target size: the control sits at the 44px floor (h-11).
  it "meets the 44px target floor" do
    render_inline(described_class.new(name: "q"))

    expect(page).to have_css("input.h-11")
  end

  # The decorative magnifier icon must be hidden from assistive tech.
  it "renders the icon as aria-hidden" do
    render_inline(described_class.new(name: "q"))

    expect(page).to have_css("svg[aria-hidden='true']")
  end

  # invalid: drives the server-validation-driven aria-invalid posture.
  it "sets aria-invalid when invalid" do
    render_inline(described_class.new(name: "q", invalid: true))

    expect(page).to have_css("input[type='search'][aria-invalid='true']")
  end

  it "is not invalid by default" do
    render_inline(described_class.new(name: "q"))

    expect(page).not_to have_css("input[aria-invalid='true']")
  end

  it "sets aria-describedby when describedby is given" do
    render_inline(described_class.new(name: "q", describedby: "search_hint"))

    expect(page).to have_css("input[type='search'][aria-describedby='search_hint']")
  end

  it "omits aria-describedby by default" do
    render_inline(described_class.new(name: "q"))

    expect(page).not_to have_css("input[aria-describedby]")
  end

  it "sets required and aria-required when required" do
    render_inline(described_class.new(name: "q", required: true))

    expect(page).to have_css("input[type='search'][required][aria-required='true']")
  end

  it "is not required by default" do
    render_inline(described_class.new(name: "q"))

    expect(page).not_to have_css("input[required]")
  end

  it "passes through name and placeholder" do
    render_inline(described_class.new(name: "q", placeholder: "Find a thing…"))

    expect(page).to have_css("input[type='search'][name='q'][placeholder='Find a thing…']")
  end
end
