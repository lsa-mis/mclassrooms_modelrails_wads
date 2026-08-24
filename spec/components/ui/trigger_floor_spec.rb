# frozen_string_literal: true

require "rails_helper"

# `trigger_class:` used to REPLACE the trigger's classes. Every other class input in these
# components merges via `cn()` — the wrapper, the panel, every menu item — and the trigger
# was the exception, on the one element carrying an ARIA contract. A caller restyling it
# silently dropped the focus indicator (WCAG 2.4.11) and the 44px target size (2.5.5 AAA).
RSpec.describe "Overlay trigger accessibility floor", type: :component do
  def render_popover(trigger_class = nil)
    opts = { label: "Account menu" }
    opts[:trigger_class] = trigger_class if trigger_class
    render_inline(UI::PopoverComponent.new(**opts)) { |c| c.with_trigger { "Open" } }
  end

  def render_dropdown(trigger_class = nil)
    opts = trigger_class ? { trigger_class: trigger_class } : {}
    render_inline(UI::DropdownMenuComponent.new(**opts)) do |c|
      c.with_trigger { "Open" }
      c.with_item { "Edit" }
    end
  end

  shared_examples "a trigger with an unremovable floor" do |renderer, selector|
    it "keeps the floor when the caller restyles it" do
      send(renderer, "text-sm text-text-muted")

      classes = page.find(selector, visible: :all)[:class]
      expect(classes).to include("focus-ring")
      expect(classes).to include("min-h-[var(--form-input-height)]")
    end

    it "still applies the caller's own classes" do
      send(renderer, "text-sm text-text-muted")

      expect(page.find(selector, visible: :all)[:class]).to include("text-sm", "text-text-muted")
    end

    # The safety control: this fix must be invisible unless you were already broken.
    it "leaves the default trigger unchanged" do
      send(renderer)

      expect(page.find(selector, visible: :all)[:class]).to include("btn-secondary")
    end
  end

  describe UI::PopoverComponent do
    include_examples "a trigger with an unremovable floor", :render_popover, "[data-floating-target=trigger]"
  end

  describe UI::DropdownMenuComponent do
    include_examples "a trigger with an unremovable floor", :render_dropdown, "[data-menu-target=trigger]"
  end
end
