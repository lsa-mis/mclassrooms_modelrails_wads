# frozen_string_literal: true

require "rails_helper"

# STRUCTURE-only component specs. The Stimulus `rating` controller's runtime
# behavior — hover preview, click-to-select — is NOT exercised here; that is
# verified by the app's system/axe specs (pass B). These specs assert the
# rendered HTML contract: group name, star buttons, per-star labels, 44px
# targets, the semantic warning token, and the hidden input.
RSpec.describe UI::RatingInputComponent, type: :component do
  it "renders a named group container" do
    render_inline(described_class.new(value: 3))

    # The star-button group must expose an accessible name so assistive tech
    # announces it as a coherent group (default "Rating").
    expect(page).to have_css("[role='group'][aria-label='Rating']")
  end

  it "allows the group label to be overridden" do
    render_inline(described_class.new(value: 3, label: "Overall quality"))

    expect(page).to have_css("[role='group'][aria-label='Overall quality']")
  end

  it "renders max star buttons each with a per-star label" do
    render_inline(described_class.new(value: 2, max: 5))

    expect(page).to have_css("button[type='button']", count: 5)
    (1..5).each do |i|
      expect(page).to have_css("button[type='button'][aria-label='Rate #{i} of 5']")
    end
  end

  it "renders each star button at the 44px target size" do
    render_inline(described_class.new(value: 0, max: 5))

    # AAA 2.5.5: each star is a >=44px hit target even though the visual star is 24px.
    expect(page).to have_css("button[type='button'].min-h-11.min-w-11", count: 5)
  end

  it "uses the semantic warning token for filled stars" do
    render_inline(described_class.new(value: 3, max: 5))

    # Stars are graphic icons (WCAG 1.4.11 → 3:1); the AAA-tuned warning-icon
    # token clears that easily. Filled = index <= value.
    expect(page).to have_css("button.text-warning-icon", count: 3)
  end

  it "uses the muted text token for empty stars" do
    render_inline(described_class.new(value: 3, max: 5))

    expect(page).to have_css("button.text-text-muted", count: 2)
  end

  it "never emits the raw yellow color" do
    render_inline(described_class.new(value: 5, max: 5))

    # Regression guard: the raw Tailwind color text-yellow-400 (a token violation)
    # must never appear — filled stars use the semantic warning token instead.
    expect(page).not_to have_css(".text-yellow-400")
  end

  it "emits a hidden input carrying the value when name is given" do
    render_inline(described_class.new(value: 4, max: 5, name: "review[rating]"))

    expect(page).to have_css("input[type='hidden'][name='review[rating]'][value='4']", visible: :all)
  end

  it "omits the hidden input without a name" do
    render_inline(described_class.new(value: 4, max: 5))

    expect(page).not_to have_css("input[type='hidden']", visible: :all)
  end

  it "clamps the value to the max" do
    render_inline(described_class.new(value: 99, max: 5, name: "stars"))

    expect(page).to have_css("input[type='hidden'][name='stars'][value='5']", visible: :all)
  end
end
