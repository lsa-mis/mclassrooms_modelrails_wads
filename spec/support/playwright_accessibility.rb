# frozen_string_literal: true

# Accessibility testing helper using axe-core. Injects axe-core JavaScript and
# runs accessibility audits. Drives Chrome through the Ferrum/CDP helpers
# (CdpHelpers, `page.driver.browser`) — the pure-Ruby CDP path — rather than
# Playwright. The module name is kept as PlaywrightAccessibility for now to
# avoid churn across the many specs that include it.
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

  # WCAG 2.2 AAA conformance is CUMULATIVE (2.0 + 2.1 + 2.2 at A/AA/AAA,
  # WCAG §5) — but axe tags each version separately (wcag2a ≠ wcag21a ≠
  # wcag22aa). Filtering on the 2.0-era tags alone silently skipped every
  # 2.1/2.2 rule on every audit (backlog #10, found via the Load-360 button).
  AXE_TAG_SET = %w[wcag2a wcag2aa wcag2aaa wcag21a wcag21aa wcag22aa].freeze

  # target-size (2.5.8 AA, 24px) ships `enabled: false` in axe 4.x — the tag
  # alone never runs it. The 44px AAA floor (2.5.5) has NO axe rule at all;
  # the mc-target-size-44 custom check below covers it.
  AXE_RULE_OVERRIDES = { "target-size" => { enabled: true } }.freeze

  DEFAULT_AXE_OPTIONS = {
    runOnly: { type: "tag", values: AXE_TAG_SET },
    rules: AXE_RULE_OVERRIDES
  }.freeze

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
    # Callers may narrow runOnly further, but the rule overrides (target-size
    # enablement) always apply, and an options hash with no runOnly gets the
    # full cumulative tag set rather than axe's open-ended default.
    options = options.symbolize_keys
    options[:runOnly] ||= DEFAULT_AXE_OPTIONS[:runOnly]
    options[:rules] = AXE_RULE_OVERRIDES.merge(options[:rules] || {})

    inject_axe

    exclude_list = Array(exclude)
    include_list = Array(include)

    # Ferrum's evaluate_async appends a resolve callback as the LAST argument of
    # the wrapping function; the async IIFE reaches it via
    # `arguments[arguments.length - 1]` (arrow functions inherit the enclosing
    # function's `arguments`). We resolve `JSON.stringify(results)` — a single
    # string round-trip that mirrors Playwright's returnByValue JSON semantics —
    # then JSON.parse below. Resolving the raw object instead would route through
    # Ferrum's handle_response/reduce_props, a recursive CDP getProperties walk
    # per nested object (thousands of round-trips over the full axe result) that
    # also `.compact`s arrays. The try/catch guarantees resolve is always called
    # so an in-IIFE throw surfaces as a raised error instead of a 20s timeout.
    raw = cdp_evaluate_async(<<~JAVASCRIPT)
        (async () => {
          try {
          const options = #{options.to_json};
          const exclude = #{exclude_list.to_json};
          const include = #{include_list.to_json};
          const context = {};
          if (include.length > 0) context.include = include;
          if (exclude.length > 0) context.exclude = exclude;

          // Settle in-flight CSS transitions/animations before auditing so
          // color-contrast is computed on the FINAL painted state, not a
          // mid-transition composite. A dialog caught mid-open at ~0.67 opacity
          // blends its (settled-AAA) background over the surface below it, and
          // axe reports a bogus sub-threshold ratio — the §2b surface-drift
          // flake (~1-in-3 under full-suite load, when the open animation is
          // still running as the sweep fires). finish() jumps each FINITE
          // animation to its end state; infinite animations (spinners) throw
          // InvalidStateError and are skipped, so this can't hang the audit.
          document.getAnimations().forEach((a) => { try { a.finish(); } catch (_) {} });
          void document.body.offsetHeight; // force reflow so computed styles reflect the settled state

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

          // ------- backlog #10: checks axe cannot perform -------
          const INTERACTIVE = 'a[href], button, input:not([type=hidden]), select, textarea, summary, [tabindex]:not([tabindex="-1"]), [role="button"], [role="link"]';
          const excludedEl = (el) => exclude.some(sel => { try { return el.closest(sel); } catch (_) { return false; } });
          const inScope = (el) => include.length === 0 || include.some(sel => { try { return el.closest(sel); } catch (_) { return false; } });
          const visibleEl = (el) => {
            const r = el.getBoundingClientRect();
            const cs = getComputedStyle(el);
            return r.width > 0 && r.height > 0 && cs.visibility !== "hidden" && cs.display !== "none";
          };
          const describe = (el) => el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") +
            (el.classList.length ? "." + [...el.classList].slice(0, 3).join(".") : "");
          const pushCheck = (id, help, nodes) => {
            if (nodes.length) results.violations.push({ id, help, impact: "serious",
              nodes: nodes.map(n => ({ html: n.el.outerHTML.slice(0, 160), target: [describe(n.el)], failureSummary: n.why })) });
          };
          const focusables = [...document.querySelectorAll(INTERACTIVE)]
            .filter(el => visibleEl(el) && !excludedEl(el) && inScope(el) && !el.disabled);

          const alphaOf = (color) => {
            if (!color || color === "transparent") return 0;
            const slash = color.match(/\\/\\s*([\\d.]+%?)\\s*\\)/);
            if (slash) return slash[1].endsWith("%") ? parseFloat(slash[1]) / 100 : parseFloat(slash[1]);
            const rgba = color.match(/rgba\\(([^)]+)\\)/);
            if (rgba) { const parts = rgba[1].split(","); return parts.length === 4 ? parseFloat(parts[3]) : 1; }
            return 1;
          };
          const hasOpaquePlate = (el) => {
            let cur = el;
            while (cur && cur !== document.documentElement) {
              if (alphaOf(getComputedStyle(cur).backgroundColor) >= 0.9) return true;
              cur = cur.parentElement;
            }
            return false;
          };

          // axe files can't-compute contrast under `incomplete` for many
          // benign reasons (an <img> INSIDE a button, partial overlaps). The
          // defect class is an interactive element with NO opaque plate
          // anywhere up-chain — contrast genuinely unguaranteed. Elements on
          // a solid ancestor are axe's limitation, not a design bug.
          for (const v of (results.incomplete || [])) {
            if (!v.id || !v.id.includes("color-contrast")) continue;
            const nodes = (v.nodes || []).filter(n => {
              const el = findNode(n.target || []);
              return el && el.closest(INTERACTIVE) && !excludedEl(el) && inScope(el) &&
                     !hasOpaquePlate(el.closest(INTERACTIVE));
            });
            if (nodes.length) results.violations.push({
              id: v.id + "-incomplete-interactive", impact: "serious", nodes,
              help: "axe could not compute contrast for an interactive element with no opaque background plate up-chain"
            });
          }

          // WCAG 2.5.5 (AAA): 44x44 minimum target. The label union counts —
          // a 20px checkbox inside a 44px-tall labelled row passes, matching
          // how the SC measures the effective target.
          const tooSmall = [];
          for (const el of focusables) {
            const cs = getComputedStyle(el);
            if (cs.display === "inline" && el.matches("a[href]")) continue; // in-text link exception
            // sr-only bypass links (skip-to-content) are clipped to ~1px while
            // blurred BY DESIGN and expand on focus — measuring the blurred
            // rect is a false positive.
            const blurredRect = el.getBoundingClientRect();
            if (blurredRect.width <= 2 && blurredRect.height <= 2 && cs.position === "absolute") continue;
            // Composite-widget interiors (panel call, 2026-07-13): menu and
            // listbox items keep desktop density — 2.5.5 is NOT CLAIMED for
            // them on fine pointers (documented conformance deviation). They
            // are still held to the 24px 2.5.8 AA floor here, and a
            // pointer:coarse rule bumps them to 44px on touch devices, the
            // population the SC protects.
            const widgetItem = el.matches("[role=menuitem],[role=menuitemcheckbox],[role=menuitemradio],[role=option]") &&
                               el.closest("[role=menu],[role=menubar],[role=listbox]");
            const floor = widgetItem ? 23.5 : 43.5;
            let r = blurredRect;
            const label = el.labels && el.labels[0];
            if (label) {
              const lr = label.getBoundingClientRect();
              r = { width: Math.max(r.right, lr.right) - Math.min(r.left, lr.left),
                    height: Math.max(r.bottom, lr.bottom) - Math.min(r.top, lr.top) };
            }
            // Layout-box fallback: getBoundingClientRect shrinks under
            // transforms — an audit racing a dialog's 200ms close animation
            // (panel at scale .95) measured 44px buttons at 42. offsetWidth/
            // Height ignore transforms; persistent scale bugs are prevented
            // at the source (no scale-* rest classes on panels).
            const w = Math.max(r.width, el.offsetWidth || 0);
            const h = Math.max(r.height, el.offsetHeight || 0);
            if (w < floor || h < floor)
              tooSmall.push({ el, why: `target ${Math.round(w)}x${Math.round(h)} — floor is ${widgetItem ? "24x24 (2.5.8 AA, widget-item deviation)" : "44x44 (2.5.5)"}` });
          }
          pushCheck("mc-target-size-44", "Touch targets must be at least 44x44 (WCAG 2.5.5 AAA; label union counts)", tooSmall);

          // A control whose composited background never reaches ~opacity over
          // media has UNKNOWABLE contrast (the Load-360 defect class). True
          // PAINT-STACK test at the control's center (rect intersection
          // false-positived on controls merely sharing a box with a sibling
          // thumbnail): walking elementsFromPoint top-down, the control (or
          // one of its descendants — a plated chip inside a tabbable tooltip
          // wrapper) with an opaque background means plated; hitting media
          // before ANY opaque background means unguaranteed contrast.
          // "Media" for contrast purposes is not only <img>/<canvas>/<video>:
          // an inline <svg>, or a photo set via CSS `background-image: url()`,
          // is just as unknowable a backdrop (2026-07-13 review). A gradient/
          // solid background-image is NOT treated as media (not a raster), but
          // its opacity is also not asserted — an opaque background-color plate
          // is still required.
          const isMedia = (node) => {
            if (node.matches && node.matches("img, canvas, video, svg")) return true;
            const bg = getComputedStyle(node).backgroundImage;
            return typeof bg === "string" && bg.includes("url(");
          };
          const overMediaUnplated = (el) => {
            const r = el.getBoundingClientRect();
            const stack = document.elementsFromPoint(r.left + r.width / 2, r.top + r.height / 2);
            if (!stack.includes(el)) return false; // center not on the control (covered/offscreen)
            for (const node of stack) {
              const opaque = alphaOf(getComputedStyle(node).backgroundColor) >= 0.9;
              if (node === el || el.contains(node)) {
                if (opaque) return false;
                continue;
              }
              if (opaque) return false;
              if (isMedia(node)) return true;
            }
            return false;
          };
          const seeThrough = focusables
            .filter(overMediaUnplated)
            .map(el => ({ el, why: "transparent control overlapping media — contrast is unknowable; add an opaque plate" }));
          pushCheck("mc-transparent-over-media", "Interactive elements over images/canvas/video need an opaque background", seeThrough);

          // WCAG 2.4.7 — deterministic CSSOM analysis, not focus mutation:
          // Chromium does not reliably honor focus({focusVisible:true}) after
          // pointer input, which made a diff-the-styles version flaky. An
          // element passes when an author :focus/:focus-visible/:focus-within
          // rule with paint-affecting declarations matches it, OR when no
          // author rule suppresses the outline (the UA default ring shows).
          const focusSelectors = [];
          const suppressSelectors = [];
          const PAINTS = ["outline-style", "outline-width", "outline", "box-shadow", "background-color", "border-color", "text-decoration-line", "color"];
          const collectRules = (rules) => { for (const rule of rules) { try {
            if (rule.cssRules && rule.cssRules.length) collectRules(rule.cssRules);
            const sel = rule.selectorText;
            if (!sel || !rule.style) continue;
            if (/:focus/.test(sel)) {
              if (!PAINTS.some(p => rule.style.getPropertyValue(p))) continue;
              for (const part of sel.split(",")) {
                if (!/:focus/.test(part)) continue;
                const stripped = part.replace(/:focus-visible|:focus-within|:focus/g, "").trim();
                if (stripped) focusSelectors.push(stripped);
              }
            } else if (["none", "0px"].includes(rule.style.getPropertyValue("outline-style") || rule.style.getPropertyValue("outline-width")) ||
                       rule.style.getPropertyValue("outline") === "0") {
              // Strip :focus* SYMMETRICALLY with the focus branch above — a
              // suppressor like `.btn:focus-visible { outline: none }` must
              // reduce to `.btn` to match during this UNFOCUSED sweep (keeping
              // the pseudo made el.matches() always false, silently missing
              // the most common way focus rings are killed; 2026-07-13 review).
              for (const part of sel.split(",")) {
                const stripped = part.replace(/:focus-visible|:focus-within|:focus/g, "").trim();
                if (stripped) suppressSelectors.push(stripped);
              }
            }
          } catch (_) {} } };
          for (const s of document.styleSheets) { try { collectRules(s.cssRules); } catch (_) {} }
          const matchesAny = (el, sels) => sels.some(sel => { try { return el.matches(sel); } catch (_) { return false; } });
          // The indicator may live on a WRAPPER via :focus-within (e.g. a
          // search box whose ring is on the bordered container) — walk up.
          const anyAncestorFocusStyle = (el) => {
            for (let a = el; a && a !== document.body; a = a.parentElement) {
              if (matchesAny(a, focusSelectors)) return true;
            }
            return false;
          };
          const noIndicator = focusables
            .filter(el => matchesAny(el, suppressSelectors) && !anyAncestorFocusStyle(el))
            .map(el => ({ el, why: "outline suppressed by author CSS with no :focus/:focus-visible paint rule matching this element or an ancestor (WCAG 2.4.7)" }));
          pushCheck("mc-focus-indicator", "Focusable elements must show a visible focus indicator (WCAG 2.4.7)", noIndicator);

          arguments[arguments.length - 1](JSON.stringify(results));
          } catch (__axeErr) {
            arguments[arguments.length - 1](JSON.stringify({
              __axe_error: (__axeErr && __axeErr.message) || String(__axeErr),
              __axe_stack: __axeErr && __axeErr.stack
            }));
          }
        })();
      JAVASCRIPT

    result = JSON.parse(raw)
    if result.is_a?(Hash) && result["__axe_error"]
      raise "axe-core audit failed in the browser: #{result["__axe_error"]}\n#{result["__axe_stack"]}"
    end

    result
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
    # Async: it AWAITS the color transitions, so it must run through
    # cdp_evaluate_async (which awaits the Promise) and resolve the ferrum
    # callback when done. The try/catch resolves `true` even on an unexpected
    # throw so a post-await failure can never hang for the full 20s wait.
    cdp_evaluate_async(<<~JS)
        (async () => {
          try {
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
          arguments[arguments.length - 1](true);
          } catch (__themeErr) {
            arguments[arguments.length - 1](true);
          }
        })();
      JS
  end

  def inject_axe
    return if cdp_evaluate("typeof window.axe !== 'undefined'")

    # `execute` (raw statement, no implicit `return`) — NOT `evaluate`, which
    # wraps in `function(){ return … }` and breaks axe-core's UMD self-assign
    # to `window`.
    cdp_execute(AXE_SOURCE)
  end
end

RSpec.configure do |config|
  config.include PlaywrightAccessibility, type: :system

  # In CI, automatically run axe accessibility audit after every system spec
  if ENV["CI"]
    config.after(:each, type: :system) do |example|
      # Deliberate-violation examples (component previews that DOCUMENT an
      # anti-pattern) opt out explicitly — tag with `skip_axe_hook: true`
      # and say why at the tag site.
      next if example.metadata[:skip_axe_hook]

      # Multi-session examples can end with an about:blank window current —
      # auditing an empty document only produces a bogus document-title
      # violation.
      next if Capybara.current_session.current_url.start_with?("about:")
      # Prepare toasts for audit:
      # - Defeat in-progress animations (element opacity, transforms)
      # - Force a solid background so axe can reliably compute color contrast.
      #   The toast's production background uses alpha transparency (oklch / 90%),
      #   which requires axe to walk up the DOM and blend with ancestors. That
      #   walk-up is sensitive to DOM state and occasionally produces a flaky
      #   "color-contrast" violation. Overriding to a solid-alpha version of
      #   the same OKLCH color gives axe a deterministic value to test against,
      #   without changing the production visual design.
      # Synchronous DOM mutation, no return value -> cdp_execute (raw statement).
      cdp_execute(<<~JS)
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

      # Audits at WCAG 2.2 Level AAA — the project's design target. The full
      # CUMULATIVE tag set (2.0+2.1+2.2 at A/AA/AAA): the previous
      # wcag2aaa-only filter ran just axe's 3 AAA-only rules and its comment
      # wrongly credited a "wcag22aaa" tag that was never passed (and which
      # covers no 44px rule anyway — the mc-* custom checks in run_axe_audit
      # handle 44px targets, focus indicators, and over-media transparency).
      # Fully qualified: this block's LEXICAL scope is outside the module, so
      # a bare constant NameErrors even though config.include provides the
      # METHODS — and only CI runs this hook, so local runs never catch it.
      results = run_axe_audit(PlaywrightAccessibility::DEFAULT_AXE_OPTIONS.dup)
      violations = results["violations"] || []

      formatted = violations.map { |v| format_violation(v) }

      expect(violations).to be_empty,
        "Accessibility violations found:#{formatted.join("\n")}"
    end
  end
end
