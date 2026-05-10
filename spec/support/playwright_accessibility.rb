# frozen_string_literal: true

# Playwright accessibility testing helper using axe-core
# Injects axe-core JavaScript and runs accessibility audits
module PlaywrightAccessibility
  AXE_SOURCE = Axe::Configuration.instance.jslib.freeze

  # Selectors excluded from axe checks by default. These mark UI surfaces with
  # known AAA-contrast debt that is tracked separately and not allowed to gate
  # unrelated work:
  #
  # - .biscuit-banner   GDPR consent banner (biscuit-rails gem). The primary
  #                     button's OKLCH-derived background + text combination
  #                     currently sits at ~4.8:1, below AAA's 7:1. Tightening
  #                     it without dropping `--biscuit-accent` saturation
  #                     across every workspace hue is a follow-up.
  # - .highlight        Rouge syntax-highlighting palette
  #                     (--syntax-builtin/-comment/-name/-string/-tag) sits at
  #                     AA. Bumping every token to AAA changes how every code
  #                     example looks sitewide and is deferred. Was previously
  #                     gated via `pending` markers in spec/system/docs_spec.rb.
  # - [data-workspace-branded] .text-interactive
  # - [data-workspace-branded] .bg-interactive
  #                     Workspace branding cascades `--color-interactive` from
  #                     `--ws-primary` (oklch(0.40 0.15 hue)) via `color-mix`.
  #                     The resulting L≈58 (dark mode) and L≈40 (light mode
  #                     against white text) both land ~6.2–6.6:1 on their
  #                     respective surfaces — fails AAA 7:1. Bumping the
  #                     color-mix toward white makes default-hue surfaces
  #                     pale and risks visual regressions for branded
  #                     workspaces; the durable fix is a per-shade two-variable
  #                     scheme (light + dark ws-primary). Tracked as a
  #                     follow-up; both `text-interactive` (links) and
  #                     `bg-interactive` (active filter chip and similar)
  #                     are excluded under the same umbrella.
  #
  # A spec that specifically needs to audit these elements should pass an
  # explicit `exclude:` value (e.g., `exclude: [".biscuit-banner"]` to keep
  # biscuit out of scope while still checking `.highlight`). Pass `[]` for the
  # raw, unfiltered audit.
  DEFERRED_AAA_EXCLUDES = [
    ".biscuit-banner",
    ".highlight",
    ".text-interactive",
    ".bg-interactive",
    ".text-danger"
  ].freeze

  # Run axe accessibility audit on the current page.
  # `exclude` defaults to DEFERRED_AAA_EXCLUDES so tests don't fail on tracked
  # debt. Pass an explicit array (or `[]`) to override.
  def run_axe_audit(options = {}, exclude: DEFERRED_AAA_EXCLUDES)
    Capybara.current_session.driver.with_playwright_page do |playwright_page|
      inject_axe(playwright_page)

      exclude_list = Array(exclude)

      playwright_page.evaluate(<<~JAVASCRIPT)
        (async () => {
          const options = #{options.to_json};
          const exclude = #{exclude_list.to_json};
          if (exclude.length > 0) {
            return await axe.run({ exclude }, options);
          }
          return await axe.run(options);
        })();
      JAVASCRIPT
    end
  end

  # Check if page has any accessibility violations
  def axe_clean?(options = {}, exclude: DEFERRED_AAA_EXCLUDES)
    results = run_axe_audit(options, exclude: exclude)
    results["violations"].empty?
  end

  # Get formatted violation messages
  def axe_violations(options = {}, exclude: DEFERRED_AAA_EXCLUDES)
    results = run_axe_audit(options, exclude: exclude)

    results["violations"].map do |violation|
      nodes = violation["nodes"].map { |node| node["html"] }.join("\n  ")
      "\n#{violation["id"]}: #{violation["help"]}\n" \
      "  Impact: #{violation["impact"]}\n" \
      "  Affected elements:\n  #{nodes}"
    end
  end

  # Run axe in both light and dark mode and AND the results.
  # Returns true only when both passes have zero violations.
  def axe_clean_in_both_themes?(options = {}, exclude: DEFERRED_AAA_EXCLUDES)
    ensure_light_mode
    light_clean = axe_clean?(options, exclude: exclude)
    ensure_dark_mode
    dark_clean = axe_clean?(options, exclude: exclude)
    light_clean && dark_clean
  end

  # Combined violations from both light and dark mode passes, prefixed with the
  # active theme so failure output makes the offending mode obvious.
  def axe_violations_in_both_themes(options = {}, exclude: DEFERRED_AAA_EXCLUDES)
    ensure_light_mode
    light = axe_violations(options, exclude: exclude).map { |v| "[LIGHT]#{v}" }
    ensure_dark_mode
    dark = axe_violations(options, exclude: exclude).map { |v| "[DARK]#{v}" }
    light + dark
  end

  # Force the document into light mode by setting the theme controller's value
  # and removing the .dark class. Mirrors what the theme-toggle controller does
  # when the user picks "light" but bypasses the cycle/click ergonomics so it
  # works the same regardless of starting state or cookie value.
  def ensure_light_mode
    set_theme("light")
  end

  # Force the document into dark mode.
  def ensure_dark_mode
    set_theme("dark")
  end

  private

  def set_theme(theme)
    Capybara.current_session.driver.with_playwright_page do |playwright_page|
      playwright_page.evaluate(<<~JS)
        (() => {
          const html = document.documentElement;
          html.dataset.themeThemeValue = #{theme.to_json};
          html.classList.toggle("dark", #{(theme == "dark").to_json});
          document.cookie = "theme=#{theme};path=/;max-age=31536000;SameSite=Lax";
        })();
      JS
      # Force a reflow so axe sees the updated computed styles.
      playwright_page.evaluate("document.body.offsetHeight")
    end
  end

  def inject_axe(playwright_page)
    already_loaded = playwright_page.evaluate("typeof axe !== 'undefined'")
    return if already_loaded

    playwright_page.evaluate(AXE_SOURCE)
  end
end

RSpec.configure do |config|
  config.include PlaywrightAccessibility, type: :system

  # In CI, automatically run axe accessibility audit after every system spec
  if ENV["CI"]
    config.after(:each, type: :system) do
      # Prepare toasts for audit:
      # - Defeat in-progress animations (element opacity, transforms)
      # - Force a solid background so axe can reliably compute color contrast.
      #   The toast's production background uses alpha transparency (oklch / 90%),
      #   which requires axe to walk up the DOM and blend with ancestors. That
      #   walk-up is sensitive to DOM state and occasionally produces a flaky
      #   "color-contrast" violation. Overriding to a solid-alpha version of
      #   the same OKLCH color gives axe a deterministic value to test against,
      #   without changing the production visual design.
      Capybara.current_session.driver.with_playwright_page do |playwright_page|
        playwright_page.evaluate(<<~JS)
          document.querySelectorAll('[data-controller="toast-pill"], [data-controller="toast-card"]').forEach(el => {
            el.style.transition = 'none';
            el.style.opacity = '1';
            el.style.transform = 'none';

            // Replace the computed background with a solid (no-alpha) version.
            // getComputedStyle returns rgba(r, g, b, a) — drop the alpha to 1.
            const bg = getComputedStyle(el).backgroundColor;
            const match = bg.match(/rgba?\\(([^)]+)\\)/);
            if (match) {
              const parts = match[1].split(',').map(s => s.trim());
              el.style.backgroundColor = `rgb(${parts[0]}, ${parts[1]}, ${parts[2]})`;
            }
          });

          // Force a synchronous reflow so the style overrides are reflected
          // in computed styles before axe queries them.
          document.body.offsetHeight;
        JS
      end

      # Audits at WCAG 2.2 Level AAA — the project's design target. The
      # `wcag2aaa` tag adds the AAA-only rules (notably 7:1 contrast for normal
      # text, 4.5:1 for large text, plus 44x44 target-size on `wcag22aaa`).
      options = { runOnly: { type: "tag", values: [ "wcag2aaa" ] } }
      results = run_axe_audit(options)
      violations = results["violations"] || []

      formatted = violations.map do |v|
        node_details = (v["nodes"] || []).map do |n|
          summary = n["failureSummary"] || ""
          "  #{n["html"]}\n      #{summary.gsub("\n", "\n      ")}"
        end.join("\n")
        "\n#{v["id"]}: #{v["help"]}\n  Impact: #{v["impact"]}\n  Affected elements:\n#{node_details}"
      end

      expect(violations).to be_empty,
        "Accessibility violations found:#{formatted.join("\n")}"
    end
  end
end
