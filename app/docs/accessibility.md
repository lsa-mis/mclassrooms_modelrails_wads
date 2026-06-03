---
title: Accessibility
description: How this template enforces WCAG 2.2 Level AAA — the axe-core gate, the helpers, and the tracked exclusions
keywords: accessibility wcag aaa axe-core contrast focus target size playwright system specs dark mode
audience: [guide, technical]
---

# Accessibility

This template targets **WCAG 2.2 Level AAA** on every screen, and it enforces that target automatically — not by review discipline alone. Accessibility is a build output that can fail CI, the same way a broken test does. New UI is expected to pass at AAA the day it ships.

## What AAA Means Here

Level AAA raises the bar above the more common AA baseline:

| Requirement | AAA standard |
|-------------|--------------|
| Contrast (normal text) | 7:1 |
| Contrast (large text) | 4.5:1 |
| Interactive target size | 44×44px minimum |
| Focus indicator | Always visible, never suppressed |

These are the headline rules the automated gate checks, alongside the rest of the `wcag2aaa` rule set.

## How the Gate Runs

Accessibility is audited with [axe-core](https://github.com/dequelabs/axe-core), injected into the page through Playwright during system specs. The audit runs only the AAA rule set:

```ruby
options = { runOnly: { type: "tag", values: [ "wcag2aaa" ] } }
```

In CI, this audit runs automatically after *every* system spec — there is no opt-in to forget. The hook lives in `spec/support/playwright_accessibility.rb`:

```ruby
# CI only — runs after each system spec
config.after(:each, type: :system) do
  options = { runOnly: { type: "tag", values: [ "wcag2aaa" ] } }
  results = run_axe_audit(options)
  expect(results["violations"]).to be_empty
end
```

If any rule fails, the spec fails and the build goes red. Locally the audit is opt-in so the suite stays fast — call the helpers on the pages you want checked.

## Auditing Locally

The `PlaywrightAccessibility` helpers are available in every system spec:

| Helper | Use |
|--------|-----|
| `axe_clean?` | true when the current page has zero violations |
| `axe_violations` | formatted violation messages; color-contrast failures include an ancestor-chain, theme, and animation debug payload |
| `axe_clean_in_both_themes?` | runs the audit in light and dark mode and ANDs the result |
| `axe_violations_in_both_themes` | combined light and dark violations, each prefixed with the active theme |

A typical check:

```ruby
it "is accessible in both themes" do
  visit dashboard_path

  expect(axe_clean_in_both_themes?).to be(true),
    axe_violations_in_both_themes.join("\n")
end
```

Because tokens are remapped under `.dark`, the both-themes helpers catch contrast regressions that surface in only one mode.

## Writing AAA-Compliant Code

The fastest way to pass the gate is to never hardcode color or size:

- **Use semantic tokens, not raw palette utilities.** `text-text-body`, `bg-surface`, and `border-border` resolve to AAA-verified values in both themes. Hardcoded utilities like `text-gray-400` or `bg-white` are not contrast-checked against the token system and drift over time. See [UI patterns](/docs/ui-patterns) and [Components](/docs/components).
- **Use `focus:ring-interactive-focus` for focus rings** so the indicator stays visible and on-brand.
- **Give interactive elements a 44×44px minimum target.** Pad small icon buttons rather than shrinking the hit area.
- **Let `.dark` do the theming.** Tokens remap automatically under the `.dark` selector, so markup rarely needs `dark:` variants.

For the token catalog and the live component states — each annotated with its accessibility contract — browse [`/lookbook`](/lookbook) in development.

## Deferred Debt and the Escape Hatch

A few surfaces carry known AAA-contrast debt that is tracked rather than allowed to block unrelated work. They live in one constant, `DEFERRED_AAA_EXCLUDES`, and are excluded from the default audit:

| Selector | Why it is deferred |
|----------|--------------------|
| `.biscuit-banner` | The GDPR consent banner's OKLCH-derived button sits at ~4.8:1; tightening it without desaturating every workspace hue is a follow-up |
| `.highlight` | The Rouge syntax-highlighting palette sits at AA; raising it to AAA changes how every code sample looks sitewide |

This list is a visible, documented ledger — not a silent bypass. Two rules keep it honest:

1. Every entry names a concrete reason and is meant to shrink, never grow.
2. To audit an excluded surface deliberately, pass an explicit `exclude:` argument; use `exclude: []` for the raw, unfiltered audit.

### Resolved

- **`.text-danger`** (resolved on `feat/ui-alert-exemplar`) — dark-mode danger text sat at 6.84:1 on `bg-surface-raised` (the lightest dark surface, neutral-800), below AAA's 7:1. Fixed at the token level by raising dark `--color-danger` / `--color-danger-icon` from `L=0.808` to `L=0.825` (now 7.08:1 measured on surface-raised, higher on the darker surfaces). The exclusion was retired and danger text is now held to AAA app-wide in both themes; `spec/system/ui/alert_component_spec.rb` proves it unscoped on the alert.

When you add UI, assume it must pass at AAA with no new exclusion. Reach for the ledger only for genuinely tracked debt — and write down why.
