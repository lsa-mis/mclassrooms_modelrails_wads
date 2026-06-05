# frozen_string_literal: true

require "rails_helper"

# Parity: UI::ButtonComponent reproduces the app's .btn-* button system
# (app/assets/tailwind/application.css @layer components) so new code can use the
# gem component and look identical to existing .btn-primary/.btn-secondary/etc.
RSpec.describe UI::ButtonComponent, "app .btn-* parity", type: :component do
  it "primary matches .btn-primary" do
    render_inline(described_class.new("Save", variant: :primary))
    b = page.find("button")
    expect(b.text).to eq("Save")
    cls = b[:class]
    expect(cls).to include("bg-interactive")
    expect(cls).to include("hover:bg-interactive-hover")
    expect(cls).to include("text-text-on-interactive")
    expect(cls).to include("min-h-[var(--form-input-height)]")
    expect(cls).to include("focus:ring-interactive-focus")
  end

  it "secondary matches .btn-secondary (bordered, neutral)" do
    render_inline(described_class.new("Cancel", variant: :secondary))
    cls = page.find("button")[:class]
    expect(cls).to include("border")
    expect(cls).to include("text-text-body")
    expect(cls).to include("hover:bg-surface-sunken")
  end

  it "danger matches .btn-danger" do
    render_inline(described_class.new("Delete", variant: :danger))
    cls = page.find("button")[:class]
    expect(cls).to include("bg-danger")
    expect(cls).to include("focus:ring-danger")
  end

  # `destructive` is a non-breaking alias for the canonical `danger` — identical render.
  it "renders the destructive alias identically to danger" do
    render_inline(described_class.new("Delete", variant: :danger))
    danger_class = page.find("button")[:class]

    render_inline(described_class.new("Delete", variant: :destructive))
    destructive_class = page.find("button")[:class]

    expect(destructive_class).to eq(danger_class)
  end

  it "text_interactive matches .btn-text + .btn-text-interactive" do
    render_inline(described_class.new("Learn more", variant: :text_interactive))
    cls = page.find("button")[:class]
    expect(cls).to include("underline")
    expect(cls).to include("text-interactive")
  end

  it "renders as a link when href is given" do
    render_inline(described_class.new("Home", href: "/", variant: :primary))
    expect(page).to have_css('a[href="/"]', text: "Home")
  end

  it "raises ArgumentError on an unknown variant (fail-loud in dev/test)" do
    expect {
      described_class.new("Save", variant: :bogus)
    }.to raise_error(ArgumentError, /unknown variant :bogus/)
  end

  it "falls back to :primary in production instead of raising" do
    # Replace Rails.env with a fresh production inquirer for this example rather than
    # stubbing a method on the shared, memoized Rails.env object.
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    render_inline(described_class.new("Save", variant: :bogus))
    expect(page.find("button")[:class]).to include("bg-interactive") # primary styling
  end
end
