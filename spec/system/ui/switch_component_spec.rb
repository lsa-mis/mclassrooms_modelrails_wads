# frozen_string_literal: true

require "rails_helper"

# ENHANCED preview-host proof for the switch component.
#
# The switch is a visually-hidden `<input type=checkbox role=switch class="peer sr-only">`
# (the `peer`) followed by two LATER-SIBLING spans inside a wrapper: the TRACK and
# the THUMB. The on/off visual is driven ENTIRELY by Tailwind's peer-* sibling
# cascade:
#
#   TRACK: bg-surface-sunken  ->  peer-checked:bg-interactive
#   THUMB: translate-x-0      ->  peer-checked:translate-x-[calc(100%-2px)]
#   TRACK focus outline:          an AAA outline on peer focus-visible (B5)
#
# The render harness only verifies class STRINGS are present — it cannot see
# whether `.peer:checked ~ .track` actually matches and recomputes the cascade.
# A broken DOM order (input not a peer, or track/thumb not later siblings) would
# pass the render harness but render a dead switch. This spec proves the cascade
# in a real browser by reading COMPUTED styles on vs off.
#
# Stable selectors (no component edit needed — see CRITICAL note below):
#   input: input[role="switch"]
#   TRACK: input[role="switch"] + span        (the input's immediate next sibling)
#   THUMB: span[aria-hidden="true"]           (the only aria-hidden span in the widget)
#
# CRITICAL: I did NOT edit the vendored switch component. The track/thumb have no
# data-* hooks, but their DOM position (input's next sibling; the aria-hidden span)
# is stable and load-bearing to the peer-* contract itself, so it is a legitimate
# selector. Adding a data attr would have meant changing the gem template too.
RSpec.describe "Switch component accessibility and visual transition", type: :system do
  PREVIEW = "/rails/view_components/ui/switch_component"

  TRACK_SELECTOR = 'input[role="switch"] + span'
  THUMB_SELECTOR = 'span[aria-hidden="true"]'

  # Read computed styles for the track + thumb off the live page.
  # `cdp_evaluate` returns a Hash with STRING keys; symbolize at the boundary so
  # the rest of the spec reads cleanly.
  def computed_switch_styles
    raw = cdp_evaluate(<<~JS)
      (() => {
        const track = document.querySelector(#{TRACK_SELECTOR.to_json});
        const thumb = document.querySelector(#{THUMB_SELECTOR.to_json});
        const ts = track ? getComputedStyle(track) : null;
        const hs = thumb ? getComputedStyle(thumb) : null;
        return {
          trackFound: !!track,
          thumbFound: !!thumb,
          trackBg: ts ? ts.backgroundColor : null,
          // Tailwind 4 implements `translate-x-*` via the native CSS `translate`
          // property (not the legacy `transform: translateX()`), so the thumb's
          // movement shows up here, while computed `transform` stays "none".
          thumbTranslate: hs ? hs.translate : null,
          thumbTransform: hs ? hs.transform : null
        };
      })()
    JS
    raw.transform_keys(&:to_sym)
  end

  describe "AAA accessibility" do
    it "off scenario has role=switch and passes AAA in both themes" do
      visit "#{PREVIEW}/off"
      expect(page).to have_css('input[role="switch"]')

      # Scope to the whole switch widget (the outer label wraps input+track+thumb
      # and the text label). No color-contrast exclude — a real failure on the
      # interactive track/thumb colors would fail here.
      scope = [ "label" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end

    it "on scenario has role=switch and passes AAA in both themes" do
      visit "#{PREVIEW}/on"
      expect(page).to have_css('input[role="switch"]')

      scope = [ "label" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  # Proves peer-checked:bg-interactive AND peer-checked:translate-x actually apply
  # — the cascade fix invisible to the render harness. If on and off compute the
  # same track background OR the same thumb translate, the cascade is dead and
  # this fails (do NOT fudge).
  describe "on/off visual transition (peer-checked cascade)" do
    it "track background-color and thumb translate DIFFER on vs off" do
      visit "#{PREVIEW}/off"
      expect(page).to have_css('input[role="switch"]')
      off = computed_switch_styles
      expect(off[:trackFound]).to be(true), "track span not found via #{TRACK_SELECTOR}"
      expect(off[:thumbFound]).to be(true), "thumb span not found via #{THUMB_SELECTOR}"

      visit "#{PREVIEW}/on"
      expect(page).to have_css('input[role="switch"]:checked')
      on = computed_switch_styles
      expect(on[:trackFound]).to be(true)
      expect(on[:thumbFound]).to be(true)

      # peer-checked:bg-interactive — the track recolors when checked.
      expect(on[:trackBg]).not_to(
        eq(off[:trackBg]),
        "track background did not change off->on (cascade broken). " \
        "off=#{off[:trackBg].inspect} on=#{on[:trackBg].inspect}"
      )

      # peer-checked:translate-x-[calc(100%-2px)] — the thumb slides when checked.
      # TW4 routes this through the CSS `translate` property; off resolves to a
      # zero offset and on to `calc(100% - 2px)`, so the two must differ.
      expect(on[:thumbTranslate]).not_to(
        eq(off[:thumbTranslate]),
        "thumb translate did not change off->on (cascade broken). " \
        "off=#{off[:thumbTranslate].inspect} on=#{on[:thumbTranslate].inspect}"
      )
      expect(on[:thumbTranslate]).to(
        include("100%"),
        "checked thumb translate should resolve the calc(100%-2px) offset; got #{on[:thumbTranslate].inspect}"
      )
    end
  end

  # Proves the AAA focus outline applies on the TRACK via the peer-focus-visible
  # cascade (converged-conventions B5). The input is `sr-only` but focusable; the
  # visible focus indicator lives on the TRACK. B5 uses an OUTLINE (not a box-shadow
  # ring) so the indicator survives overflow:hidden clipping and forced-colors mode.
  #
  # Approach: programmatic `.focus()` does not reliably trigger `:focus-visible` in
  # Chromium, nor does a JS-dispatched (untrusted) synthetic Tab keydown — Chromium's
  # focus-modality heuristic only latches "keyboard" on a TRUSTED keyboard event. So we
  # blur whatever's focused and Tab-navigate onto the switch input via REAL CDP-dispatched
  # key presses — the browser's own native tab-navigation is what makes :focus-visible
  # latch true (verified empirically against this driver's Chrome; JS-level tricks don't).
  #
  # The TRACK carries `transition-all`, which ANIMATES the (animatable) outline-width
  # 0 -> 2px over the transition duration. We poll a few frames until it settles so we
  # read the resolved focus indicator, not a mid-transition frame. (The old box-shadow
  # ring proof never needed this because it read the non-animated --tw-ring-shadow
  # custom property; an outline's longhands are real animatable computed values.)
  describe "focus-visible outline (peer-focus-visible cascade)" do
    it "renders the AAA focus outline on the track when the switch input is keyboard-focused" do
      visit "#{PREVIEW}/off"
      expect(page).to have_css('input[role="switch"]')

      unfocused = track_outline

      # Real CDP Tab presses from a blurred state — walk the native tab order until
      # landing on the switch input (bounded, so a genuine focus-order regression fails
      # loudly instead of looping).
      cdp_execute("document.activeElement && document.activeElement.blur()")
      reached_switch = (1..10).any? do
        cdp_press("Tab")
        cdp_evaluate(%(document.activeElement === document.querySelector('input[role="switch"]')))
      end
      raise "could not reach the switch input via Tab navigation" unless reached_switch

      focused = cdp_evaluate_async(<<~JS)
        (async () => {
          const track = document.querySelector(#{TRACK_SELECTOR.to_json});
          // Poll until the transitioned outline-width settles at its 2px target
          // (or a generous deadline, so a genuine no-outline bug still fails loudly).
          let cs = getComputedStyle(track);
          const deadline = performance.now() + 800;
          while (cs.outlineWidth !== "2px" && performance.now() < deadline) {
            await new Promise((r) => requestAnimationFrame(r));
            cs = getComputedStyle(track);
          }
          const input = document.querySelector('input[role="switch"]');
          arguments[arguments.length - 1]({
            focusVisible: input.matches(":focus-visible"),
            focused: document.activeElement === input,
            outlineStyle: cs.outlineStyle,
            outlineWidth: cs.outlineWidth,
            outlineColor: cs.outlineColor
          });
        })()
      JS

      expect(focused["focused"]).to be(true), "switch input did not receive focus"
      expect(focused["focusVisible"]).to(
        be(true),
        "the engine did not latch :focus-visible for the focused switch input, " \
        "so the peer-focus-visible cascade cannot be exercised here"
      )

      # Unfocused: no outline (the track gets its outline only on peer focus-visible).
      expect(unfocused[:style]).to(
        eq("none"),
        "expected no outline when unfocused, got style=#{unfocused[:style].inspect}"
      )

      # Focus-visible: the track resolves the AAA 2px solid outline in the interactive
      # focus color. This is the actual proof the peer-focus-visible outline applies.
      expect(focused["outlineStyle"]).to(
        eq("solid"),
        "track outline did not become solid on focus-visible — the peer focus outline did not apply. " \
        "unfocused=#{unfocused.inspect} focused style=#{focused["outlineStyle"].inspect}"
      )
      expect(focused["outlineWidth"]).to(
        eq("2px"),
        "focused outline should be 2px; got #{focused["outlineWidth"].inspect}"
      )
      expect(focused["outlineColor"]).not_to(
        satisfy { |c| c.nil? || c.to_s.empty? || c == "transparent" || c.to_s.include?("rgba(0, 0, 0, 0)") },
        "the outline color should resolve to the interactive focus token on focus, " \
        "got #{focused["outlineColor"].inspect}"
      )
    end
  end

  # Reads the track's computed outline longhands off the live page.
  def track_outline
    result = cdp_evaluate(<<~JS)
      (() => {
        const cs = getComputedStyle(document.querySelector(#{TRACK_SELECTOR.to_json}));
        return { style: cs.outlineStyle, width: cs.outlineWidth, color: cs.outlineColor };
      })()
    JS
    result.transform_keys(&:to_sym)
  end
end
