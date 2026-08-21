# frozen_string_literal: true

require "rails_helper"

# The `side` × `align` matrix, proven in the browser rather than by asserting class strings.
# It earns its keep: before the anchor-positioning migration, `side: :left`/`:right` emitted
# both `left-0` and `right-full`, which CSS resolves by dropping `right` — so the panel sat
# ON its trigger instead of beside it, for every left/right placement, undetected.
#
# The anchor is centred first so no `position-try-fallbacks` flip can fire; this asserts the
# base placement, not the collision behaviour (which is exercised by the fallback firing
# naturally in the stacking-context previews).
RSpec.describe "Popover placement", type: :system do
  let(:gap) { 8 } # mt-2 / mb-2 / mr-2 / ml-2

  def place_and_open(side, align)
    visit "/rails/view_components/ui/popover_component/playground?side=#{side}&align=#{align}"
    page.execute_script(<<~JS)
      const w = document.querySelector("[data-controller=floating]");
      w.style.position = "fixed"; w.style.left = "600px"; w.style.top = "600px";
    JS
    find("[data-floating-target=trigger]").click
    expect(page).to have_css("[data-floating-target=panel]")
  end

  def geometry
    page.evaluate_script(<<~JS)
      (() => {
        const t = document.querySelector("[data-floating-target=trigger]").getBoundingClientRect();
        const p = document.querySelector("[data-floating-target=panel]").getBoundingClientRect();
        const near = (a, b) => Math.abs(a - b) <= 2;
        let side = "none";
        if (near(p.top - t.bottom, #{gap})) side = "bottom";
        else if (near(t.top - p.bottom, #{gap})) side = "top";
        else if (near(p.left - t.right, #{gap})) side = "right";
        else if (near(t.left - p.right, #{gap})) side = "left";
        return JSON.stringify({ side, dx: Math.round(p.left - t.left), dy: Math.round(p.top - t.top) });
      })()
    JS
  end

  # For bottom/top, `align` edge-aligns horizontally; for left/right, vertically.
  { bottom: :dx, top: :dx, left: :dy, right: :dy }.each do |side, axis|
    describe "side: #{side}" do
      %i[start center end].each do |align|
        it "places the panel on the #{side} for align: #{align}" do
          place_and_open(side, align)

          expect(JSON.parse(geometry).fetch("side")).to eq(side.to_s)
        end
      end

      it "orders start / center / end along the #{axis == :dx ? "horizontal" : "vertical"} axis" do
        offsets = %i[start center end].map do |align|
          place_and_open(side, align)
          JSON.parse(geometry).fetch(axis.to_s)
        end

        expect(offsets).to eq(offsets.sort.reverse), "expected start > center > end, got #{offsets.inspect}"
      end
    end
  end
end
