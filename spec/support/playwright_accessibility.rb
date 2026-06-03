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
  #
  # `.text-danger` was previously deferred here: dark-mode danger text sat below
  # AAA on `bg-surface-raised` (the lightest dark surface, neutral-800) at
  # 6.84:1. Fixed at the TOKEN level on branch `feat/ui-alert-exemplar` by
  # raising dark `--color-danger`/`--color-danger-icon` from L=0.808 to L=0.825
  # (now 7.08:1 measured on surface-raised, higher on the darker surfaces). It
  # is no longer excluded — every danger-text usage app-wide is held to AAA in
  # both themes. `spec/system/ui/alert_component_spec.rb` proves it unscoped on
  # the alert.
  #
  # `.text-interactive` and `.bg-interactive` were previously deferred under
  # the workspace-branded color-mix umbrella; the durable two-variable scheme
  # (`--ws-primary-light` + `--ws-primary-dark`, see
  # `app/assets/tailwind/application.css` "Workspace Branding Override")
  # made them AAA-compliant deterministically, so they are no longer excluded.
  #
  # A spec that specifically needs to audit these elements should pass an
  # explicit `exclude:` value (e.g., `exclude: [".biscuit-banner"]` to keep
  # biscuit out of scope while still checking `.highlight`). Pass `[]` for the
  # raw, unfiltered audit.
  DEFERRED_AAA_EXCLUDES = [
    ".biscuit-banner",
    ".highlight"
  ].freeze

  # Run axe accessibility audit on the current page.
  # `exclude` defaults to DEFERRED_AAA_EXCLUDES so tests don't fail on tracked
  # debt. Pass an explicit array (or `[]`) to override.
  #
  # `include` scopes the audit to one or more DOM subtrees (axe `context`
  # selectors). Use it to audit a single COMPONENT rather than the whole page —
  # e.g. a preview-host page whose minimal layout emits `best-practice`
  # advisories (landmark-one-main, page-has-heading-one) that are not WCAG and
  # not about the component under test. Scoping to the component keeps those
  # host-chrome advisories out of scope WITHOUT excluding any rule. Do NOT use
  # it to scope a real color-contrast failure out of the audit.
  #
  # Color-contrast violations are enriched with a `_debug` payload (ancestor
  # chain computed styles, theme state, in-flight animations) so failure
  # messages reveal the cascade reality at scan time. See §2b flake
  # investigation for the motivating case.
  def run_axe_audit(options = {}, exclude: DEFERRED_AAA_EXCLUDES, include: nil)
    Capybara.current_session.driver.with_playwright_page do |playwright_page|
      inject_axe(playwright_page)

      exclude_list = Array(exclude)
      include_list = Array(include)

      playwright_page.evaluate(<<~JAVASCRIPT)
        (async () => {
          const options = #{options.to_json};
          const exclude = #{exclude_list.to_json};
          const include = #{include_list.to_json};
          const context = {};
          if (include.length > 0) context.include = include;
          if (exclude.length > 0) context.exclude = exclude;
          const results = (context.include || context.exclude)
            ? await axe.run(context, options)
            : await axe.run(options);

          const findNode = (target) => {
            try { return document.querySelector(target[target.length - 1]); }
            catch (_) { return null; }
          };

          const captureAncestors = (el) => {
            const chain = [];
            let current = el;
            while (current && current !== document.documentElement) {
              const cs = getComputedStyle(current);
              const transition = cs.transition && cs.transition !== "all 0s ease 0s" ? cs.transition : "none";
              chain.push({
                tag: current.tagName,
                classes: Array.from(current.classList).join(" "),
                backgroundColor: cs.backgroundColor,
                opacity: cs.opacity,
                transition: transition
              });
              current = current.parentElement;
            }
            return chain;
          };

          const captureAnimations = () => {
            try {
              return document.getAnimations().map(a => ({
                type: a.constructor.name,
                currentTime: a.currentTime,
                effectTargetTag: a.effect && a.effect.target ? a.effect.target.tagName : null,
                effectTargetClass: a.effect && a.effect.target ? a.effect.target.className : null
              }));
            } catch (_) { return []; }
          };

          const captureTheme = () => ({
            htmlClasses: Array.from(document.documentElement.classList).join(" "),
            cookieTheme: (document.cookie.match(/theme=(\\w+)/) || [])[1] || null
          });

          for (const v of (results.violations || [])) {
            if (!v.id || !v.id.includes("color-contrast")) continue;
            for (const node of (v.nodes || [])) {
              const el = findNode(node.target || []);
              node._debug = {
                ancestorChain: el ? captureAncestors(el) : [],
                theme: captureTheme(),
                animations: captureAnimations(),
                timestamp: Date.now(),
                elementFound: !!el
              };
            }
          }

          return results;
        })();
      JAVASCRIPT
    end
  end

  # Check if page has any accessibility violations
  def axe_clean?(options = {}, exclude: DEFERRED_AAA_EXCLUDES, include: nil)
    results = run_axe_audit(options, exclude: exclude, include: include)
    results["violations"].empty?
  end

  # Get formatted violation messages. Color-contrast violations include the
  # ancestor-chain / theme / animation debug payload captured by `run_axe_audit`.
  def axe_violations(options = {}, exclude: DEFERRED_AAA_EXCLUDES, include: nil)
    results = run_axe_audit(options, exclude: exclude, include: include)
    Array(results["violations"]).map { |v| format_violation(v) }
  end

  # Render a single violation as a multi-line string. Color-contrast violations
  # surface the diagnostic payload (`_debug` on each node) so the cascade and
  # theme state at scan time are visible in CI logs.
  def format_violation(violation)
    id     = violation["id"].to_s
    help   = violation["help"]
    impact = violation["impact"]
    nodes  = Array(violation["nodes"])

    lines = []
    lines << "\n#{id}: #{help}"
    lines << "  Impact: #{impact}"
    lines << "  Affected elements:"

    nodes.each do |node|
      lines << "  #{node["html"]}"
      summary = node["failureSummary"].to_s
      lines << "      #{summary.gsub("\n", "\n      ")}" unless summary.empty?
      next unless id.include?("color-contrast")

      debug = node["_debug"]
      if debug.nil?
        lines << "    (no diagnostic payload captured)"
        next
      end

      lines << "    Ancestor chain:"
      Array(debug["ancestorChain"]).each_with_index do |a, i|
        indent  = "      " + ("  " * i)
        tag     = a["tag"]
        classes = a["classes"].to_s.empty? ? "" : ".#{a["classes"]}"
        lines << "#{indent}#{tag}#{classes}  bg=#{a["backgroundColor"]}  opacity=#{a["opacity"]}  transition=#{a["transition"]}"
      end

      theme = debug["theme"] || {}
      lines << "    Theme: html=#{theme["htmlClasses"].inspect} cookie=#{theme["cookieTheme"].inspect}"

      animations = Array(debug["animations"])
      if animations.empty?
        lines << "    Animations: none"
      else
        lines << "    Animations:"
        animations.each do |a|
          lines << "      #{a["type"]} target=#{a["effectTargetTag"] || "?"} class=#{a["effectTargetClass"].inspect} t=#{a["currentTime"]}"
        end
      end
    end

    lines.join("\n")
  end

  # Run axe in both light and dark mode and AND the results.
  # Returns true only when both passes have zero violations.
  def axe_clean_in_both_themes?(options = {}, exclude: DEFERRED_AAA_EXCLUDES, include: nil)
    ensure_light_mode
    light_clean = axe_clean?(options, exclude: exclude, include: include)
    ensure_dark_mode
    dark_clean = axe_clean?(options, exclude: exclude, include: include)
    light_clean && dark_clean
  end

  # Combined violations from both light and dark mode passes, prefixed with the
  # active theme so failure output makes the offending mode obvious.
  def axe_violations_in_both_themes(options = {}, exclude: DEFERRED_AAA_EXCLUDES, include: nil)
    ensure_light_mode
    light = axe_violations(options, exclude: exclude, include: include).map { |v| "[LIGHT]#{v}" }
    ensure_dark_mode
    dark = axe_violations(options, exclude: exclude, include: include).map { |v| "[DARK]#{v}" }
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
        (async () => {
          const html = document.documentElement;
          html.dataset.themeThemeValue = #{theme.to_json};
          html.classList.toggle("dark", #{(theme == "dark").to_json});
          document.cookie = "theme=#{theme};path=/;max-age=31536000;SameSite=Lax";
          // Force reflow so the cascade recomputes.
          document.body.offsetHeight;
          // The flip triggers `transition-colors` on many elements (150ms).
          // Axe samples computed styles, so without awaiting these transitions
          // we capture mid-flight interpolations and get phantom AAA failures
          // (the §2b "surface drift" symptom). Filter to CSSTransition so we
          // never wait on infinite CSSAnimations (e.g. animate-spin). 500ms
          // cap is defense-in-depth against runaway transitions.
          const transitions = document.getAnimations().filter(a => a instanceof CSSTransition);
          await Promise.race([
            Promise.allSettled(transitions.map(t => t.finished)),
            new Promise(r => setTimeout(r, 500))
          ]);
        })();
      JS
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

      formatted = violations.map { |v| format_violation(v) }

      expect(violations).to be_empty,
        "Accessibility violations found:#{formatted.join("\n")}"
    end
  end
end
