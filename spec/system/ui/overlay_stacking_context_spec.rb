# frozen_string_literal: true

require "rails_helper"

# `position: absolute`/`fixed` escapes overflow clipping but never a *stacking context*:
# a floating panel's `z-50` is scoped to the nearest positioned ancestor with a z-index.
# A `sticky z-40` header (app/views/shared/_header.html.erb) and a `backdrop-blur` navbar
# (UI::NavbarComponent) are both ordinary chrome here, and both establish one — so no
# z-index on the panel lifts it above a sibling in the root context.
#
# The fix is the top layer: `showPopover()` paints the panel above every stacking context
# while leaving it in the DOM, so the Stimulus actions inside it stay bound.
#
# The catch, and why only the anchor-positioned band is promoted: the top layer makes the
# *initial containing block* the containing block, so a panel placed with `absolute` +
# `top-full` offsets resolves against the viewport and lands off its trigger. Panels placed
# with CSS anchor positioning are already `position: fixed` against the viewport, so
# promotion changes paint order only.
RSpec.describe "Overlay stacking context", type: :system do
  # What a user actually cares about: is the panel clickable, or is something else painted
  # on top of it? `elementFromPoint` answers exactly that.
  def occluded?(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector("#{selector}");
        const box = el.getBoundingClientRect();
        const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
        return !(hit === el || el.contains(hit));
      })()
    JS
  end

  def gap_below_trigger(panel, trigger)
    page.evaluate_script(<<~JS)
      (() => {
        const t = document.querySelector("#{trigger}").getBoundingClientRect();
        const p = document.querySelector("#{panel}").getBoundingClientRect();
        return Math.round(p.top - t.bottom);
      })()
    JS
  end

  describe "a dropdown menu placed by CSS anchor positioning" do
    let(:panel) { "[data-menu-target=menu]" }
    let(:trigger) { "[data-menu-target=trigger]" }

    before do
      visit "/rails/view_components/ui/dropdown_menu_component/inside_stacking_context"
      find(trigger).click
      expect(page).to have_css(panel)
    end

    it "keeps the panel above page content that outranks its stacking context" do
      expect(occluded?(panel)).to be(false)
    end

    # The half the top layer would silently destroy if the panel were placed with
    # `absolute` offsets instead of anchor positioning.
    it "still anchors the panel to its trigger" do
      expect(gap_below_trigger(panel, trigger)).to be_between(2, 8)
    end

    it "still sizes the panel from its own classes, not the UA popover box" do
      width = page.evaluate_script(%{Math.round(document.querySelector("#{panel}").getBoundingClientRect().width)})

      expect(width).to be_between(128, 400) # min-w-[8rem], shrink-wrapped to its items
    end
  end

  describe "a popover placed by CSS anchor positioning" do
    let(:panel) { "[data-floating-target=panel]" }
    let(:trigger) { "[data-floating-target=trigger]" }

    before do
      visit "/rails/view_components/ui/popover_component/inside_stacking_context"
      find(trigger).click
      expect(page).to have_css(panel)
    end

    it "keeps the panel above page content that outranks its stacking context" do
      expect(occluded?(panel)).to be(false)
    end

    it "still anchors the panel to its trigger" do
      expect(gap_below_trigger(panel, trigger)).to be_between(4, 12) # mt-2 == 8px
    end

    it "still sizes the panel from its own classes, not the UA popover box" do
      width = page.evaluate_script(%{Math.round(document.querySelector("#{panel}").getBoundingClientRect().width)})

      expect(width).to eq(288) # w-72
    end
  end

  # Browsers that support the Popover API but NOT anchor positioning (Firefox, Safari at
  # time of writing) fall back to `absolute` + `top-full` offsets. Promoting THAT lands the
  # panel against the viewport instead of its trigger — measured at 1320px adrift. So the
  # guard is the invariant itself, not a feature name: promote only what is already
  # `position: fixed`, where the containing-block change is a no-op.
  describe "a panel on the pre-Baseline absolute fallback" do
    let(:panel) { "[data-menu-target=menu]" }
    let(:trigger) { "[data-menu-target=trigger]" }

    before do
      visit "/rails/view_components/ui/dropdown_menu_component/inside_stacking_context"
      # Emulate a browser without anchor positioning: the panel resolves to `absolute`.
      page.execute_script(<<~JS)
        const css = document.createElement("style");
        css.textContent = "[data-menu-target=menu] { position: absolute !important; top: 100% !important; left: 0 !important; }";
        document.head.appendChild(css);
      JS
      find(trigger).click
      expect(page).to have_css(panel)
    end

    it "is not promoted to the top layer" do
      promoted = page.evaluate_script(<<~JS)
        (() => { const el = document.querySelector("#{panel}");
                 try { return el.matches(":popover-open") } catch (e) { return false } })()
      JS

      expect(promoted).to be(false)
    end

    it "stays anchored to its trigger" do
      expect(gap_below_trigger(panel, trigger)).to be_between(0, 12)
    end
  end

  # The rest of the anchor-positioning migration. Same contract for each: the panel escapes
  # the stacking context AND stays tethered to its trigger. The second half is the one that
  # fails loudly if a component is promoted while still on `absolute` offsets.
  # `anchor` is the element carrying `anchor-name`, which is what the panel is tethered to.
  # For the pickers that is the whole field wrapper (caption + input + hint) — the same box
  # `top-full` resolved against before the migration, so placement is unchanged.
  {
    "date_picker" => { open: "[data-date-picker-target=trigger]", panel: "[data-date-picker-target=popover]",
                       anchor: "[data-controller=date-picker]", gap: 4 },
    "timepicker" => { open: "[data-timepicker-target=trigger]", panel: "[data-timepicker-target=popover]",
                      anchor: "[data-controller=timepicker]", gap: 4 },
    "navigation_menu" => { open: "[data-navigation-menu-target=trigger]", panel: "[data-navigation-menu-target=content]",
                           anchor: "[data-controller=navigation-menu]", gap: 6 }
  }.each do |component, sel|
    describe "#{component} inside a stacking context" do
      before do
        visit "/rails/view_components/ui/#{component}_component/inside_stacking_context"
        find(sel[:open]).hover
        find(sel[:open]).click
        expect(page).to have_css(sel[:panel], visible: :visible)
      end

      it "keeps the panel above page content that outranks its stacking context" do
        expect(occluded?(sel[:panel])).to be(false)
      end

      it "still hangs the panel off its anchor by the gap margin" do
        expect(gap_below_trigger(sel[:panel], sel[:anchor])).to be_between(sel[:gap] - 2, sel[:gap] + 2)
      end
    end
  end

  # combobox is the one panel whose width is tied to its trigger. `w-full` cannot survive
  # `position: fixed` — against the viewport it would mean the whole screen — so the modern
  # path takes its width from `anchor-size(width)`. That is the half a plain position-area
  # migration would silently get wrong.
  describe "combobox inside a stacking context" do
    let(:panel) { "[data-combobox-target=panel]" }
    let(:field) { "[data-controller~=combobox]" }

    before do
      visit "/rails/view_components/ui/combobox_component/inside_stacking_context"
      find("[data-combobox-target=input]").click
      expect(page).to have_css(panel)
    end

    it "keeps the panel above page content that outranks its stacking context" do
      expect(occluded?(panel)).to be(false)
    end

    it "still matches the width of its field" do
      widths = page.evaluate_script(<<~JS)
        (() => {
          const f = document.querySelector("#{field}").getBoundingClientRect();
          const p = document.querySelector("#{panel}").getBoundingClientRect();
          return JSON.stringify([Math.round(f.width), Math.round(p.width)]);
        })()
      JS
      field_width, panel_width = JSON.parse(widths)

      expect(panel_width).to be_within(2).of(field_width)
    end
  end

  # mega_menu's panel spans its bar, so it carries the same anchor-size() risk as combobox:
  # `w-full` against the viewport would be the whole screen.
  it "keeps the mega menu panel the width of its bar" do
    visit "/rails/view_components/ui/mega_menu_component/default"
    find("[data-mega-menu-target=trigger]").click
    expect(page).to have_css("[data-mega-menu-target=panel]")

    widths = page.evaluate_script(<<~JS)
      (() => {
        const bar = document.querySelector("[data-controller~=mega-menu]").getBoundingClientRect();
        const panel = document.querySelector("[data-mega-menu-target=panel]").getBoundingClientRect();
        return JSON.stringify([Math.round(bar.width), Math.round(panel.width)]);
      })()
    JS
    bar_width, panel_width = JSON.parse(widths)

    expect(panel_width).to be_within(2).of(bar_width)
  end
end
