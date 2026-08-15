# frozen_string_literal: true

module UI
  # # Command palette
  #
  # A search-as-you-type palette: a text input that filters a list of actions,
  # shown over a dimming scrim and centered like a modal dialog. Opened on a
  # `with_trigger` click or the global `⌘K` / `Ctrl+K` shortcut; filtering and
  # keyboard navigation live in the `command` Stimulus controller shipped
  # alongside this component.
  #
  # ## Use when
  # - You need a keyboard-first launcher to jump to pages or fire actions
  #   (the spotlight / ⌘K pattern).
  #
  # ## Don't use when
  # - A trigger opens a short list of *actions* with no search — use
  #   `dropdown_menu` (the APG menu-button pattern).
  # - You're selecting a value to submit in a form — use a `select`/listbox.
  #
  # ## Accessibility contract (WAI-ARIA APG combobox + listbox)
  # - **Guarantees:** the search input is a `role="combobox"` with
  #   `aria-expanded`, `aria-controls` (→ the list) and `aria-autocomplete="list"`;
  #   the list is a named `role="listbox"`; the controller promotes each
  #   `[data-command-value]` item to `role="option"` with a stable id and tracks
  #   the highlighted option via `aria-activedescendant` (DOM focus stays on the
  #   input — ↑/↓ move the active option, Enter activates it, Escape closes).
  #   The input and items carry the AAA `focus-ring`; the empty-state message is
  #   an i18n-labelled live region.
  # - **You supply:** an optional `with_trigger` slot and the grouped item markup
  #   (use the exposed `GROUP_WRAPPER` / `GROUP` / `ITEM` / `SHORTCUT` /
  #   `SEPARATOR` constants). Each actionable item must carry a
  #   `data-command-value` (the text the filter matches on).
  #
  # ## Sizes
  # `sm` · `md` · `lg` — the centered panel's max width.
  class CommandComponent < ApplicationComponent
    renders_one :trigger

    # Scrim dims the page; it carries no text (decorative, aria-hidden), so it
    # uses the neutral ramp rather than a content/surface token.
    OVERLAY = "fixed inset-0 z-50 bg-neutral-950/80"
    DIALOG  = "fixed left-[50%] top-[50%] z-50 w-full translate-x-[-50%] translate-y-[-50%] " \
              "overflow-hidden rounded-lg border border-border bg-surface-overlay shadow-lg"
    SEARCH  = "flex h-10 w-full items-center gap-2 border-b border-border px-3"
    # The input keeps DOM focus (combobox pattern) and carries the AAA offset
    # focus-ring itself; min-h-11 holds the 44px target floor (WCAG 2.5.5 AAA).
    # Both were regressions caught by the open-state audit (#463): the old
    # comment claimed a row-level ring no CSS actually painted.
    INPUT   = "flex-1 min-h-11 bg-transparent text-sm text-text-body outline-none focus-ring placeholder:text-text-muted"
    LIST    = "max-h-[300px] scroll-py-1 overflow-x-hidden overflow-y-auto p-1"
    EMPTY   = "py-6 text-center text-sm text-text-muted"

    # Panel max-width per size.
    SIZES = {
      sm: "max-w-sm",
      md: "max-w-lg",
      lg: "max-w-2xl"
    }.freeze

    # Wrap each group of items in a div with this class.
    GROUP_WRAPPER = "overflow-hidden p-1 text-text-heading"
    # Apply to the heading element (p/span) inside a group wrapper.
    GROUP         = "px-2 py-1.5 text-xs font-medium text-text-muted"
    # Apply to each actionable item button/link. `focus-ring` keeps the AAA offset
    # outline when an item takes DOM focus (e.g. Tab); `aria-selected:` styles the
    # controller-tracked active option for pointer + keyboard parity.
    ITEM          = "relative flex w-full cursor-default select-none items-center gap-2 rounded-sm " \
                    "px-2 py-1.5 text-sm text-text-body outline-none focus-ring " \
                    "hover:bg-surface-sunken hover:text-text-heading " \
                    "aria-selected:bg-surface-sunken aria-selected:text-text-heading " \
                    "[&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4 " \
                    "[&_svg:not([class*='text-'])]:text-text-muted"
    # Place inside an ITEM as the last child to show a keyboard shortcut on the right.
    SHORTCUT      = "ml-auto text-xs tracking-widest text-text-muted"
    # Horizontal rule between groups. An <hr>'s implicit role="separator" is an
    # ILLEGAL child of role="listbox" (axe aria-required-children, critical) —
    # the controller neutralizes any hr inside the list to role="presentation"
    # at open, so caller markup can't break the listbox contract; give your hr
    # role="presentation" anyway so the static render is honest too.
    SEPARATOR     = "-mx-1 h-px bg-border"

    def initialize(size: :md, **html_attrs)
      @size        = coerce_size(size)
      @extra_class = html_attrs.delete(:class)
      # Merge the controller wiring into any caller `data:` so a passed-through
      # `data:` attr can't clobber `data-controller` and silently break Stimulus.
      @data        = { controller: "command" }.merge(html_attrs.delete(:data) || {})
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:div, data: @data, **@html_attrs) do
        concat content_tag(:span, trigger, data: { action: "click->command#open" }, class: "contents") if trigger
        concat panel
      end
    end

    private

    LIST_ID = "command-list"

    def panel
      content_tag(:div, data: { command_target: "panel" }, hidden: true) do
        concat content_tag(:div, nil,
          class: OVERLAY,
          data: { action: "click->command#close" },
          "aria-hidden": "true")
        concat content_tag(:div,
          class: cn(DIALOG, SIZES.fetch(@size), @extra_class),
          role: "dialog",
          "aria-modal": "true",
          "aria-label": I18n.t("modelrails_ui.command.dialog_label", default: "Command palette"),
          # `esc`, not `escape` — Stimulus's KeyboardEvent filter vocabulary
          # (every other floating component here uses keydown.esc). The
          # `escape` spelling is an unknown filter that never matches, which
          # left the documented Escape-closes behavior dead until the
          # keyboard-driven spec caught it (#463).
          data: { action: "keydown.esc@window->command#close" }) {
          concat search_bar
          concat content_tag(:div,
            class: LIST,
            id: LIST_ID,
            role: "listbox",
            "aria-label": I18n.t("modelrails_ui.command.list_label", default: "Commands"),
            data: { command_target: "list" }) {
            concat content
          }
          concat content_tag(:div,
            I18n.t("modelrails_ui.command.empty", default: "No results found."),
            class: EMPTY,
            role: "status",
            data: { command_target: "empty" },
            hidden: true)
        }
      end
    end

    def search_bar
      content_tag(:div, class: SEARCH) do
        concat search_icon
        concat tag.input(
          type: "text",
          role: "combobox",
          placeholder: I18n.t("modelrails_ui.command.placeholder", default: "Type a command or search…"),
          "aria-label": I18n.t("modelrails_ui.command.input_label", default: "Search commands"),
          "aria-expanded": "true",
          "aria-controls": LIST_ID,
          "aria-autocomplete": "list",
          autocomplete: "off",
          spellcheck: "false",
          class: INPUT,
          data: {
            command_target: "input",
            action: "input->command#filter keydown->command#navigate"
          }
        )
      end
    end

    def search_icon
      raw('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="shrink-0 text-text-muted" aria-hidden="true"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>') # rubocop:disable Layout/LineLength
    end

    # Fail loud on an unknown size in development/test so misuse is caught
    # immediately; fall back to :md in production so a bad size never 500s a page.
    # (Rails.respond_to?(:env) stays correct in the gem's Rails-less render tests,
    # which define Rails without booting Rails.env.)
    def coerce_size(size)
      size = size.to_sym
      return size if SIZES.key?(size)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::CommandComponent: unknown size #{size.inspect}. " \
          "Expected one of: #{SIZES.keys.join(", ")}."
      end

      :md
    end
  end
end
