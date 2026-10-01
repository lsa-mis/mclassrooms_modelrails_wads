---
title: UI Patterns & Design Tokens
description: Form builder, icons, modals, toasts, design token architecture, accessibility patterns, and recipes for the pages the template repeats
keywords: tailwind design tokens oklch dark mode form builder icons modal toast accessibility wcag aria focus signals notification bell severity non-text contrast danger-strong recipes settings page list empty state search pagination sortable table preferences card public page
code:
  settings_page:
    - app/views/layouts/settings.html.erb
    - app/views/shared/_settings_page_header.html.erb
    - app/views/settings/sessions/index.html.erb
    - spec/code_smells/settings_layout_opt_in_spec.rb
    - spec/code_smells/settings_page_padding_spec.rb
  empty_list:
    - app/components/ui/list_group_component.rb
    - app/components/ui/list_group_item_component.rb
    - app/views/shared/_empty_state.html.erb
    - app/views/operations/users/index.html.erb
  searchable_list:
    - app/components/ui/search_input_component.rb
    - app/views/shared/_pagination.html.erb
    - app/views/shared/_pager.html.erb
    - app/views/operations/users/index.html.erb
  sortable_table:
    - app/views/shared/_sortable_header.html.erb
    - app/views/shared/_pagination.html.erb
    - app/components/ui/scroll_area_component.rb
    - app/views/workspaces/members/index.html.erb
    - spec/code_smells/bordered_containers_are_not_the_page_surface_spec.rb
  preferences_card:
    - app/views/shared/_preferences_card.html.erb
    - app/views/shared/_preferences_row.html.erb
    - app/views/shared/_toggle.html.erb
    - app/views/settings/notification_preferences/_delivery_card.html.erb
  public_page:
    - app/views/shared/_hero.html.erb
    - app/views/shared/_section.html.erb
    - app/views/pages/about.html.erb
---

# UI Patterns & Design Tokens

ModelRails uses TailwindCSS 4 with a three-layer design token system, a custom form builder, and reusable UI components.

## Design Token Architecture

Tokens are organized in three layers under `app/assets/tailwind/tokens/`:

### 1. Primitives (`_primitives.css`)

Map Tailwind color families to custom properties. **To retheme the entire app, swap the color family names.**

| Palette | Default | Used for |
|---------|---------|----------|
| Primary | Sky | Buttons, links, focus rings |
| Secondary | Indigo | Accents, prose links |
| Neutral | Slate | Text, surfaces, borders |

Example: change `--primary-700: var(--color-sky-700)` to `--primary-700: var(--color-purple-700)` to switch from sky to purple.

### 2. Semantic Tokens (`_semantic.css`)

Role-based aliases that define **what colors are for**, not what they are. Dark mode is handled entirely in this layer — views never need `dark:` prefixes for token-backed colors.

| Category | Tokens | Example |
|----------|--------|---------|
| Surfaces | `surface`, `surface-raised`, `surface-overlay`, `surface-sunken` | `bg-surface-raised` |
| Text | `text-heading`, `text-body`, `text-muted`, `text-on-interactive` | `text-text-muted` |
| Interactive | `interactive`, `interactive-hover`, `interactive-focus` | `bg-interactive` |
| Borders | `border`, `border-strong`, `border-focus` | `border-border` |

### 3. Signal Tokens (`_signals.css`)

Fixed-meaning colors that don't shift with theming. Red is always danger, green is always success.

| Signal | Tokens |
|--------|--------|
| Danger | `danger`, `danger-surface`, `danger-icon`, `danger-hover`, `danger-border` |
| Warning | `warning`, `warning-surface`, `warning-icon`, `warning-hover`, `warning-border` |
| Success | `success`, `success-surface`, `success-icon`, `success-hover`, `success-border` |
| Info | `info`, `info-surface`, `info-icon`, `info-hover`, `info-border` |

#### Signals in graphics: the notification bell

The notification bell is the reference case for using signal tokens on a **graphic** rather than on text, and it encodes two rules worth knowing before you color any icon or indicator.

**Text contrast vs. non-text contrast.** The bell *icon* is tinted with the base signal tokens (`text-danger`, `text-warning`, `text-info`, `text-success`) — the same AAA (7:1) foreground colors used for flash messages and links — with a stacked white drop-shadow outline for legibility on arbitrary avatar backgrounds. The *indicator dot* variant (on the avatar/hamburger) is a different animal: it's decorative, so the applicable spec is WCAG **1.4.11 non-text contrast (3:1 for graphical objects)**, not **1.4.6 enhanced text contrast (7:1)**. That relaxation is legitimate only because the severity meaning doesn't live in the dot alone — it's also exposed textually in the user menu's Notifications row `aria-live` region.

**The red identity-shift problem.** An AAA-readable red on dark surfaces must sit at high OKLCH lightness (dark-mode `--color-danger` is L=0.825), and at that lightness red drifts toward coral/pink — on a bell-sized graphic it stops reading as "danger red." So danger alone gets a `-strong` variant: in light mode `--color-danger-strong` simply aliases `--color-danger` (the AAA warm red already reads as true red), while in dark mode it's a fire-engine red at L=0.65. The bell icon uses `dark:text-danger-strong`, and the danger dot uses `bg-danger-strong`. Because dark-mode `-strong` sits *below* the AAA text threshold (roughly 4–5:1 — AA only), it is for graphics and small accents exclusively: never use it for general text content, and never place a text descendant inside a `bg-danger-strong` fill. Do not extend the `-strong` pattern to other severities — only red has the high-lightness identity shift; amber, green, and sky stay recognizably themselves at AAA lightness. The canonical rule lives in `app/assets/tailwind/tokens/_signals.css`.

**Motion.** Only the danger dot pulses. Users with `prefers-reduced-motion` still get an instant static indicator, and everyone else gets attention-routing for the highest-severity events without warnings and info becoming noisy.

### Using Tokens in Views

```erb
<%# Correct — uses semantic tokens, adapts to dark mode automatically %>
<div class="bg-surface-raised text-text-heading border border-border">

<%# Avoid — hardcoded colors don't adapt %>
<div class="bg-white text-gray-900 border border-gray-200">
```

### Dark Mode

Dark mode uses a class-based toggle (`.dark` on `<html>`) instead of a media query. This enables the three-way user preference (light / dark / system). All semantic and signal tokens remap automatically when `.dark` is present.

### Workspace Branding

Workspace-scoped routes emit two OKLCH custom properties and a
`data-workspace-branded` marker on `<main>`, activating a cascade that
recolors the interactive tokens for that workspace:

```erb
<main data-workspace-branded
      style="--ws-primary-light: oklch(0.40 0.15 <hue>); --ws-primary-dark: oklch(0.78 0.10 <hue>);">
```

The two-variable scheme:

- `--ws-primary-light` (L=0.40) — used in light mode; hits 7:1 AAA on white.
- `--ws-primary-dark` (L=0.78) — used in dark mode; hits 7:1 AAA on slate-800.

The cascade (in `app/assets/tailwind/application.css` under the "Workspace
Branding Override" block) remaps:

- Light mode: `--color-interactive` ← `var(--ws-primary-light)`, hover/subtle
  derived via `color-mix(..., black|white)`.
- Dark mode: `--color-interactive` ← `var(--ws-primary-dark)` directly (no
  color-mix), hover/subtle derived via `color-mix(..., white|black)`.

Why direct OKLCH literals in dark mode: the previous design used
`color-mix(--ws-primary, white)` to lighten the dark-mode brand color.
That produced flaky AAA contrast in CI's Cuprite/axe renderer because
OKLCH color-mix resolution varied across Chromium/Ubuntu builds. Direct
literals are deterministic. See `project_flaky_tests_followup.md §2`
for the investigation.

The `primary_color` column on `workspaces` is an integer OKLCH hue (0–360)
with default `210` (the app's sky base). When the column matches the
default, the cascade computes values identical to the untouched tokens —
no visual change. Explicit hue changes light up immediately.

**Contrast caveat.** The `oklch(0.40 0.15 <hue>)` formula yields AAA-level
(7:1) contrast on white for most hues, but perceived lightness in OKLCH
varies by hue at a fixed `L` coordinate. Yellow-green hues in the
~80–140 range read as lighter than the coordinate suggests and can dip
below AAA (and in places below AA) on white backgrounds. The model
validation allows any integer 0–360, so workspace owners who pick a hue
in this band get buttons whose contrast is not guaranteed. This is a
known gap and will be addressed alongside the planned OKLCH
color-strategy unification; the default (`210`, sky) always meets AAA.

## Form Builder

ModelRails includes `TailwindFormBuilder`, set as the default form builder — a fork
seam over `UI::FormBuilder` (the vendored, regenerable parent). It provides:

- **Automatic labels** with required indicators
- **Error display** inline below fields as plain text — the focused `error_summary`
  (below) is the actual live-region announcement, not the inline message
- **Hint text** below the control, linked via `aria-describedby` (error-first when
  both a hint and an error are present)
- **ARIA attributes** — `aria-required`, `aria-invalid`, `aria-describedby` are set
  automatically; native HTML `required` is never emitted, and every `form_with`
  renders `novalidate` (`FormDefaultsHelper`), so a failed submit — blank *or*
  malformed — always reaches the server and gets a real error response. The input
  types stay (`type="email"` still picks the email keyboard and drives autofill);
  only the browser's own validation bubble is suppressed. A form that genuinely
  wants native validation opts out with `html: { novalidate: false }`. Build forms
  with `form_with` — `form_for`/`form_tag`, or a component calling `form_with`
  rather than `helpers.form_with`, skip the default, and a code-smell spec says so
- **Consistent styling** — all fields use token-backed border, focus ring, and error
  states

### Available Methods

`text_field`, `email_field`, `password_field`, `url_field`, `tel_field`, `number_field`, `date_field`, `search_field`, `text_area`, `select`, `checkbox` (canonical; `check_box` is an alias), `collection_checkboxes` (alias `collection_check_boxes`), `collection_radio_buttons`, `file_field`, `submit`, `error_summary`

### Field Options

| Option | Type | Purpose |
|--------|------|---------|
| `label:` | String | Custom label text (auto-generated from attribute name if omitted) |
| `required:` | Boolean | Adds required indicator and `aria-required` |
| `help:` | String | Help text shown below the field, linked via `aria-describedby` |

### Error States

When a field has validation errors, the builder automatically:
- Switches border to `border-danger`
- Adds `aria-invalid="true"`
- Renders a plain error paragraph below the field (no `role="alert"` — a field-level
  live region never fires on a server-rendered response). Call `f.error_summary` once
  per form for the real, focused announcement mechanism.

## Icon System

SVG icons are loaded from `app/assets/icons/{outline,solid}/` and cached via `IconRegistry`.

### Usage

```erb
<%= icon(:arrow_left, size: :sm) %>
<%= icon(:check, size: :lg, style: :solid) %>
<%= icon(:trash, aria_label: "Delete item") %>
```

### Sizes

| Size | Classes |
|------|---------|
| `:xs` | `w-3 h-3` |
| `:sm` | `w-4 h-4` |
| `:md` | `w-5 h-5` (default) |
| `:lg` | `w-6 h-6` |

### Accessibility

Icons are `aria-hidden="true"` by default (decorative). Pass `aria_label:` to make them meaningful — this adds `role="img"` and the label.

## Modals

**Partial:** `shared/_modal.html.erb`

Uses the native `<dialog>` element with a Stimulus controller for open/close management.

### Usage

```erb
<%= render "shared/modal", title: "Confirm action", size: :md do %>
  <p>Modal content here.</p>
<% end %>
```

### Sizes

| Size | Max width |
|------|-----------|
| `:sm` | `max-w-sm` |
| `:md` | `max-w-lg` (default) |
| `:lg` | `max-w-3xl` |
| `:full` | `max-w-5xl` |

### Features

- Animated entrance (scale 95→100, opacity 0→1)
- Backdrop click closes the modal
- Escape key closes the modal
- Focus trapped inside the modal while open
- `aria-modal="true"`, `aria-labelledby`, `aria-describedby`

## Toast Notifications

**Partials:** `shared/_toasts.html.erb`, `_toast_pill.html.erb`, `_toast_card.html.erb`

Two display styles based on severity:

| Style | Position | Types | Behavior |
|-------|----------|-------|----------|
| **Pill** | Top center | success, notice, info | Auto-dismiss with progress bar |
| **Card** | Bottom center | alert, error | Persistent until closed |

### Timing

- Duration: 500ms per word + 1s buffer (minimum 5s, maximum 15s)
- Multiple toasts stagger with a 2s delay between each

### Usage

Toasts are driven by Rails flash messages:

```ruby
redirect_to @workspace, notice: t(".success")
```

The layout renders flash messages as the appropriate toast type automatically.

## Confirmation Dialogs

**Partial:** `shared/_confirm_dialog.html.erb`

For destructive actions. Two variants:

| Variant | Icon | Colors | Use for |
|---------|------|--------|---------|
| `:danger` | Exclamation triangle | Red | Deleting, deactivating |
| `:info` | Information circle | Blue | Informational confirmations |

## Accessibility Standards

ModelRails targets **WCAG 2.2 Level AAA**:

| Pattern | Implementation |
|---------|---------------|
| Touch targets | `--form-input-height` token (default 44px) drives `TailwindFormBuilder` inputs and the `.btn-touch-target` utility. Many existing partials still use the literal `min-h-[44px]` and migrate as touched. |
| Focus indicators | The `focus-ring` utility (2px offset outline) consistently — never `focus:ring-*` box-shadows, which vanish in forced-colors mode |
| Color contrast | Default interactive token is primary-800 (7.56:1 AAA on white). On workspace-branded routes, contrast varies by hue — see Workspace Branding caveat below. |
| Skip navigation | `sr-only` link to `#main-content` at top of every page |
| Screen readers | ARIA labels, live regions, roles on all dynamic content |
| Motion | Animations respect `prefers-reduced-motion` |
| Form fields | Required indicators, error messages with `role="alert"`, help text linked |

## Layout Structure

The application layout (`layouts/application.html.erb`) provides:

1. Skip-to-content link (screen reader accessible)
2. Sticky header with navigation, theme toggle, user menu
3. Toast container (renders flash messages)
4. Main content area (`<main id="main-content">`)
5. Footer with clustered nav, centered copyright, and cookie settings button
6. Cookie consent banner (Biscuit) — shown once on first visit

## Recipes

The sections above describe parts. A recipe is how the parts go together into
a page this template builds more than once. Each one names its parts by path,
a view to copy from, and the guard that holds the rule where there is one.

Recipes made only of `UI::*` components belong in the `modelrails_ui` docs.
These are the ones built from this app's own partials, and the page's `code:`
front matter indexes them by name. `spec/docs/ui_recipes_spec.rb` reads that
index: a partial listed under a recipe fails the suite when no view in the
recipe renders it, so a recipe cannot go on describing a page that has changed.
When a view moves on, update the recipe or point it at another view.

### A page in the settings shell

A settings page gets its sidebar, its section strip on small screens and its
`<main>` from `app/views/layouts/settings.html.erb`, which a controller opts
into with `layout "settings"`. That `<main>` carries no vertical padding of
its own, so the page supplies it through its top-level wrapper:

| Wrapper | Width |
| --- | --- |
| `.page-container` | `max-w-2xl` |
| `.page-container-wide` | `max-w-4xl` |

Both classes set the vertical padding as well as the width, which is why a
wrapper that uses one adds no `py-*` of its own. The title line is
`app/views/shared/_settings_page_header.html.erb`:

```erb
<div class="page-container">
  <%= render "shared/settings_page_header",
        title: t("settings.sessions.index.title"),
        description: t("settings.sessions.index.description") %>
</div>
```

`title_html:` stands in for `title:` when the heading needs markup, and the
caller escapes any user input in it first. `badges:` takes rendered badge
markup and sets it beside the title.

Copy from `app/views/settings/sessions/index.html.erb`. Two guards hold the
shape: `spec/code_smells/settings_layout_opt_in_spec.rb` fails when a settings
controller with page templates declares neither the layout nor a reviewed
ruling, and `spec/code_smells/settings_page_padding_spec.rb` fails when a
wrapper supplies no vertical padding, supplies it twice, or sets a `max-w-*`
by hand.

### A list that may be empty

Rows without columns go in `ui :list_group`
(`app/components/ui/list_group_component.rb` and
`app/components/ui/list_group_item_component.rb`), and the branch with no rows
renders `app/views/shared/_empty_state.html.erb` in the list's place:

```erb
<% if @users.any? %>
  <%= ui :list_group do %>
    <% @users.each do |user| %>
      <%= ui :list_group_item do %>
        <%= link_to user.full_name, operations_user_path(user) %>
      <% end %>
    <% end %>
  <% end %>
<% elsif @query.present? %>
  <%= render "shared/empty_state", message: t("operations.users.index.no_match") %>
<% else %>
  <%= render "shared/empty_state", message: t("operations.users.index.empty") %>
<% end %>
```

There are two empty branches because "nothing matched" and "nothing here yet"
are different things to tell someone. The partial takes `message:`, and
`action_text:` with `action_url:` as a pair; the action renders only when both
are given.

A row that holds its own links or buttons stays a plain `ui :list_group_item`.
Pass `href:` only when the row itself is the destination.

Copy from `app/views/operations/users/index.html.erb`.

### A searchable, paged list

The search box is a GET form, so a query is a URL that can be reloaded. Outside
the form builder the control is `ui :search_input`
(`app/components/ui/search_input_component.rb`). Its `label:` repeats the
visible `<label>` text: the component emits its own `aria-label`, and a
mismatch fails WCAG 2.5.3 Label in Name.

Paging is `app/views/shared/_pagination.html.erb`. It takes `pagy:`, prints the
range being shown, and renders `app/views/shared/_pager.html.erb`, which holds
the `pagy.series_nav` call and accepts `frame:` to target a Turbo Frame. Both
render nothing when there is one page.

Copy from `app/views/operations/users/index.html.erb`. Inside the form builder
the control is `form.search_field` instead;
`app/views/workspaces/members/index.html.erb` does that inside a Turbo Frame
and announces the new count through an `aria-live` region.

### A sortable table

Rows with columns are a `<table>` inside a card: `bg-surface-raised rounded-lg
border border-border shadow-sm overflow-hidden`. The surface is part of the
recipe. `bg-surface` is the page, and a bordered box painted with it fails
`spec/code_smells/bordered_containers_are_not_the_page_surface_spec.rb`.

Each sortable column is `app/views/shared/_sortable_header.html.erb`, which
renders the whole `<th>` so that `aria-sort` sits on the header its link
sorts. It takes `title:`, `column:`, `current_sort:`, `current_direction:` and
`url:`, a callable that builds the link for a sort and a direction. `frame:`
names the Turbo Frame to swap.

`ui :scroll_area` (`app/components/ui/scroll_area_component.rb`) wraps the
table alone, so the pagination beneath it stays put while the table scrolls
sideways.

Copy from `app/views/workspaces/members/index.html.erb`.

### A preferences card

`app/views/shared/_preferences_card.html.erb` is rendered as a layout, with
`title:` and an optional `description:`, and its block is the rows:

```erb
<%= render layout: "shared/preferences_card",
      locals: { title: t("notifications.preferences.delivery_methods.heading") } do %>
  <%= render "shared/preferences_row",
        icon_name: "computer_desktop",
        icon_color: :info,
        title: t("notifications.preferences.delivery_methods.items.in_app.title"),
        description: t("notifications.preferences.delivery_methods.items.in_app.description"),
        control: in_app_control %>
<% end %>
```

Each row is `app/views/shared/_preferences_row.html.erb`. `icon_color:` is one
of `:info`, `:success`, `:warning` or `:danger`, and any other value falls back
to a neutral tile. `control:` is captured markup, here
`app/views/shared/_toggle.html.erb` in a form that submits itself on change.
Pass the toggle `visible_label: false`: the row already shows the title, and a
second visible label repeats it.

Copy from `app/views/settings/notification_preferences/_delivery_card.html.erb`.

### A public page

A public page is a stack of full-width bands. `app/views/shared/_hero.html.erb`
opens it, and each band after that is `app/views/shared/_section.html.erb`,
which takes `title:`, `subtitle:` and `bg:` and yields the content.

Copy from `app/views/pages/about.html.erb`, which alternates `bg: "bg-surface"`
and `bg: "bg-surface-raised"` so that neighboring bands read apart.

## Footer Structure

**Partial:** `shared/_footer.html.erb`

The footer is a two-row layout with responsive behavior.

### Row 1 — brand, clustered navigation, dev trigger

- **Brand:** site logo + name, links to root
- **Product cluster** (`<nav aria-label="Product">`): About, Docs
- **Vertical divider** — 14px tall `border-l border-border`, `aria-hidden`, only rendered at `sm:` and above
- **Legal & privacy cluster** (`<nav aria-label="Legal and privacy">`): Privacy, Contact, Cookie settings
- **Dev-only trigger** on the far right (desktop) — the accessibility-simulation drop-up, only rendered in `Rails.env.development?`

### Row 2 — centered copyright

A horizontal rule (`border-t border-border`) separates the two rows, followed by a centered `text-xs text-text-muted` paragraph with the current year and the `footer.copyright` i18n key.

### Responsive behavior

| Breakpoint | Row 1 layout |
| ---------- | ------------ |
| `< 640px` (mobile) | `flex-col items-center gap-6` — brand, clusters, dev trigger stack vertically |
| `640–1023px` (tablet) | `flex-row flex-wrap justify-center gap-4` — wraps naturally |
| `≥ 1024px` (desktop) | `flex-row flex-nowrap justify-start gap-6` — brand left, clusters mid, `lg:flex-1` spacer pushes dev trigger to right |

### Cookie settings button

Biscuit's gem normally renders a `position: fixed` "Manage cookies" button in the bottom-left corner. ModelRails hides it via `.biscuit-manage-link { display: none !important; }` in `app/assets/tailwind/application.css` and replaces it with a footer-integrated `<button>` that reopens the preferences panel via `footer_controller.js`:

```js
// app/javascript/controllers/footer_controller.js
reopenCookies(event) {
  event.preventDefault()
  document.querySelector(".biscuit-manage-link")?.click()
}
```

Dispatching a synthetic click to the gem's (hidden) button decouples the footer from Biscuit's Stimulus target scope — the integration works purely through the DOM and needs no gem-side coordination.

### Footer accessibility

- Two named `<nav>` landmarks allow screen readers to announce and skip clusters
- Vertical and horizontal dividers are decorative (`aria-hidden` where needed)
- All footer links and the Cookie settings button use `inline-flex items-center min-h-[44px] px-2` — meets WCAG 2.5.5 AAA (44×44 target size)
