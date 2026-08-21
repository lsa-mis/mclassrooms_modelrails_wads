# frozen_string_literal: true

require "rails_helper"

# `<details>` has no `disabled` attribute, so a disabled disclosure is expressed the way
# ARIA intends: announced via `aria-disabled`, removed from the tab order, and made
# pointer-inert. No JS — the component stays CSS-only.
RSpec.describe UI::CollapsibleComponent, type: :component do
  def collapsible(**opts)
    render_inline(described_class.new(**opts)) do |c|
      c.with_trigger { "Details" }
      "body"
    end
  end

  it "is operable by default" do
    collapsible

    summary = page.find("summary")
    expect(summary["aria-disabled"]).to be_nil
    expect(summary["tabindex"]).to be_nil
  end

  it "announces a disabled disclosure and takes it out of the tab order" do
    collapsible(disabled: true)

    summary = page.find("summary")
    expect(summary["aria-disabled"]).to eq("true")
    expect(summary["tabindex"]).to eq("-1")
  end

  # Without this the summary still toggles on click even while announced as disabled.
  it "makes a disabled summary pointer-inert" do
    collapsible(disabled: true)

    expect(page).to have_css("summary.pointer-events-none")
  end

  # A disabled disclosure that is already open stays open — disabling blocks the control,
  # it does not collapse content out from under the reader.
  it "leaves an open disabled disclosure open" do
    collapsible(disabled: true, open: true)

    expect(page).to have_css("details[open]")
  end
end
