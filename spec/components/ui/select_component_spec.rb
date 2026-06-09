# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::SelectComponent, type: :component do
  it "renders a native select with options" do
    render_inline(described_class.new(options: %w[Draft Published]))

    expect(page).to have_css("select")
    expect(page).to have_css("select option", text: "Draft")
    expect(page).to have_css("select option", text: "Published")
  end

  # AAA semantic tokens (the design-token guarantee), not raw Tailwind:
  it "renders with AAA semantic tokens" do
    render_inline(described_class.new(options: %w[A B]))

    expect(page).to have_css("select.border-border-strong")
    expect(page).to have_css("select.focus-ring")
  end

  # WCAG 2.5.5 target size: the control sits at the 44px floor (--form-input-height).
  it "meets the 44px target floor" do
    render_inline(described_class.new(options: %w[A B]))

    expect(page).to have_css('select.min-h-\\[var\\(--form-input-height\\)\\]')
  end

  # invalid: drives a visible danger ring/border, not just aria-invalid.
  it "carries a danger ring token for the invalid state" do
    render_inline(described_class.new(options: %w[A B]))

    expect(page).to have_css('select.aria-invalid\\:ring-danger')
  end

  it "marks the right option as selected" do
    render_inline(described_class.new(options: %w[Draft Published], selected: "Published"))

    expect(page).to have_css("select option[value='Published'][selected]", text: "Published")
    expect(page).not_to have_css("select option[value='Draft'][selected]")
  end

  it "adds a leading blank option when include_blank is set" do
    render_inline(described_class.new(options: %w[Draft Published], include_blank: true))

    expect(page).to have_css("select option:first-child[value='']")
  end

  it "sets aria-invalid when invalid" do
    render_inline(described_class.new(options: %w[A B], invalid: true))

    expect(page).to have_css("select[aria-invalid='true']")
  end

  it "omits aria-invalid when not invalid" do
    render_inline(described_class.new(options: %w[A B]))

    expect(page).not_to have_css("select[aria-invalid]")
  end

  it "sets aria-describedby when describedby is given" do
    render_inline(described_class.new(options: %w[A B], describedby: "status-error"))

    expect(page).to have_css("select[aria-describedby='status-error']")
  end

  it "uses an explicit id attribute" do
    render_inline(described_class.new(options: %w[A B], id: "my_select"))

    expect(page).to have_css("select#my_select")
  end

  it "falls back the id to a sanitized name" do
    render_inline(described_class.new(options: %w[A B], name: "post[status]"))

    expect(page).to have_css("select#post_status_")
  end

  it "always emits an id with neither id nor name" do
    render_inline(described_class.new(options: %w[A B]))

    expect(page).to have_css("select[id]")
  end
end
