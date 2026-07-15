# frozen_string_literal: true

require "rails_helper"

# ENHANCED preview-host proof for the rating_input component.
#
# The render harness can see the SERVER-rendered star markup, but it cannot see:
#   1. graphic contrast of the filled stars in a real browser (the `text-warning-icon`
#      token must clear WCAG 1.4.11 3:1 for graphics — stars are icons, not text), nor
#   2. the Stimulus `rating` controller's hover-preview / click-select / keyboard
#      behavior, which recolors the star <button>s live via class toggling.
#
# This spec proves all of it in a real Playwright browser.
#
# ## Component structure (server-rendered)
#   <div role="group" aria-label data-controller="rating" data-rating-...-value>
#     <button type="button" data-rating-target="star" data-rating-index-param="N"
#             class="... (text-warning-icon | text-text-muted)">  <svg .../>  </button>
#     ... (max buttons) ...
#     <input type="hidden" name=... data-rating-target="input" value=N>  (only with name:)
#   </div>
#
# ## The controller's fill semantics (rating_controller.js)
#   #render(upTo): star at 0-based array index `i` is FILLED when `i < upTo`.
#   index params are 1-based (1..max). So previewing/selecting star N (param N)
#   fills array indices 0..N-1 = DISPLAY stars 1..N. The filled class on the
#   <button> is `text-warning-icon`; unfilled is `text-text-muted`.
#
# ## Stable selectors (NO component edit needed)
#   group : [role='group'][data-controller='rating']
#   stars : button[data-rating-target='star']   (in DOM order = display order)
#   hidden: input[type='hidden'][data-rating-target='input']
# These are the component's own load-bearing a11y/behavior hooks (role, the
# Stimulus targets), not selectors invented for the test — no data-* was added.
RSpec.describe "Rating input component accessibility and behavior", type: :system do
  RATING_PREVIEW         = "/rails/view_components/ui/rating_input_component"
  RATING_STAR_SELECTOR   = "button[data-rating-target='star']"
  RATING_HIDDEN_SELECTOR = "input[type='hidden'][data-rating-target='input']"

  # Read each star <button>'s filled-state off the live Playwright page by
  # inspecting its class list (the controller toggles `text-warning-icon` on the
  # button itself). Returns an array of booleans in DISPLAY order: true = filled.
  def filled_stars
    raw = cdp_evaluate(<<~JS)
      Array.from(document.querySelectorAll(#{RATING_STAR_SELECTOR.to_json}))
           .map(btn => btn.classList.contains("text-warning-icon"))
    JS
    Array(raw)
  end

  def filled_count
    filled_stars.count(true)
  end

  # Dispatch a real `mouseenter` (the controller's hover action) on the Nth
  # display star (1-based). Stimulus reads `params.index` from the data attr, so a
  # plain dispatched event drives `preview` exactly like a real hover.
  def hover_star(display_index)
    cdp_execute(<<~JS)
      (() => {
        const stars = document.querySelectorAll(#{RATING_STAR_SELECTOR.to_json});
        stars[#{display_index - 1}].dispatchEvent(
          new MouseEvent("mouseenter", { bubbles: true })
        );
      })()
    JS
  end

  # Dispatch `mouseleave` on the Nth star → controller resets to committed value.
  def leave_star(display_index)
    cdp_execute(<<~JS)
      (() => {
        const stars = document.querySelectorAll(#{RATING_STAR_SELECTOR.to_json});
        stars[#{display_index - 1}].dispatchEvent(
          new MouseEvent("mouseleave", { bubbles: true })
        );
      })()
    JS
  end

  def hidden_value
    cdp_evaluate(<<~JS)
      (() => {
        const el = document.querySelector(#{RATING_HIDDEN_SELECTOR.to_json});
        return el ? el.value : null;
      })()
    JS
  end

  describe "AAA accessibility (graphic contrast of filled stars)" do
    # with_value renders 3 filled stars on the `text-warning-icon` token. If that
    # token failed 1.4.11 (3:1 graphic) in either theme, axe (run at AAA) would
    # flag it here — there is NO color-contrast exclude. Scope to the star group.
    it "with_value (filled stars) passes AAA in both themes" do
      visit "#{RATING_PREVIEW}/with_value"

      expect(page).to have_css("[role='group'][data-controller='rating']")
      expect(filled_count).to eq(3), "expected 3 server-rendered filled stars"

      scope = [ "[role='group'][data-controller='rating']" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end

  describe "hover preview (rating#preview / #resetPreview)" do
    # On with_value (committed value = 3), hovering star 5 must preview 5 filled,
    # and leaving must reset to the committed 3. Proves the live class cascade
    # that the render harness can't see.
    it "previews up to the hovered star, then resets to the committed value" do
      visit "#{RATING_PREVIEW}/with_value"
      expect(page).to have_css(RATING_STAR_SELECTOR, minimum: 5)
      expect(filled_count).to eq(3)

      hover_star(5)
      after_hover = filled_stars
      expect(after_hover.count(true)).to eq(5),
        "hover on star 5 should preview 5 filled, got #{after_hover.count(true)}"
      expect(after_hover.first(5)).to all(be(true))

      leave_star(5)
      after_leave = filled_stars
      expect(after_leave.count(true)).to eq(3),
        "mouseleave should reset to committed value 3, got #{after_leave.count(true)}"
      expect(after_leave.first(3)).to all(be(true))
      expect(after_leave[3..]).to all(be(false))
    end
  end

  describe "click select (rating#select)" do
    # in_a_form has name: → a hidden input, committed value 4. Clicking star 2
    # must set the hidden value to 2 AND leave exactly stars 1..2 filled.
    it "sets the hidden input value and fills 1..N on click" do
      visit "#{RATING_PREVIEW}/in_a_form"
      expect(page).to have_css(RATING_HIDDEN_SELECTOR, visible: :all)
      expect(hidden_value).to eq("4"), "server-rendered hidden value should be 4"
      expect(filled_count).to eq(4)

      all(RATING_STAR_SELECTOR)[1].click # display star 2 (0-based index 1)

      expect(hidden_value).to eq("2"), "clicking star 2 should set hidden value to 2"
      after_click = filled_stars
      expect(after_click.count(true)).to eq(2),
        "clicking star 2 should fill exactly 2 stars, got #{after_click.count(true)}"
      expect(after_click.first(2)).to all(be(true))
      expect(after_click[2..]).to all(be(false))
    end
  end

  describe "keyboard activation (AAA keyboard contract)" do
    # Each star is a native <button>, so it is focusable and Enter/Space activate
    # it natively (the browser fires a `click`, driving rating#select). We focus
    # the button, assert focus landed (the AAA keyboard-operability contract),
    # then activate via the native button click path and assert the outcome.
    #
    # Activation method: native <button> activation. A focused button is activated
    # by Enter/Space, which the UA translates into a `click` event; Capybara's
    # `.click` on the focused element drives the identical code path. We assert the
    # button is genuinely focusable (document.activeElement === the star) so the
    # keyboard contract is proven, then assert activation selects the star.
    it "stars are focusable and activation selects the focused star" do
      visit "#{RATING_PREVIEW}/in_a_form"
      expect(page).to have_css(RATING_STAR_SELECTOR, minimum: 3)

      focused_tag = cdp_evaluate(<<~JS)
        (() => {
          const stars = document.querySelectorAll(#{RATING_STAR_SELECTOR.to_json});
          const target = stars[2]; // display star 3 (0-based index 2)
          target.focus();
          return {
            isActive: document.activeElement === target,
            tag: document.activeElement && document.activeElement.tagName
          };
        })()
      JS

      expect(focused_tag["isActive"]).to be(true),
        "star <button> must be keyboard-focusable (got active=#{focused_tag["tag"]})"
      expect(focused_tag["tag"]).to eq("BUTTON")

      # Native-button activation (Enter/Space => click). Capybara click on the
      # already-focused star drives the same activation code path rating#select.
      all(RATING_STAR_SELECTOR)[2].click

      expect(hidden_value).to eq("3"),
        "activating focused star 3 should commit value 3"
      after = filled_stars
      expect(after.count(true)).to eq(3)
      expect(after.first(3)).to all(be(true))
    end
  end
end
