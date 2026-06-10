# frozen_string_literal: true

module UI
  # # Command palette
  #
  # A search-as-you-type launcher (the ⌘K / spotlight pattern): a combobox input
  # that filters a list of actions, shown over a scrim and centered like a modal.
  # Open it from the `with_trigger` slot or the global `⌘K` / `Ctrl+K` shortcut.
  #
  # ## Use when
  # - A keyboard-first user needs to jump to a page or fire an action by typing.
  #
  # ## Don't use when
  # - It's a short list of actions with no search — use `dropdown_menu`.
  # - You're picking a value to submit in a form — use a `select`/listbox.
  #
  # ## Accessibility contract (WAI-ARIA APG combobox + listbox)
  # - **Guarantees:** the input is a `role="combobox"` (`aria-expanded` /
  #   `aria-controls` / `aria-autocomplete="list"`) controlling a named
  #   `role="listbox"`; the controller promotes each `[data-command-value]` item to
  #   `role="option"` and tracks the highlighted one via `aria-activedescendant`
  #   (DOM focus stays on the input — ↑/↓ move the active option, Enter activates,
  #   Escape closes). The input + items carry the AAA `focus-ring`; the empty state
  #   is an i18n live region.
  # - **You supply:** an optional `with_trigger` and grouped item markup styled with
  #   the exposed `GROUP_WRAPPER` / `GROUP` / `ITEM` / `SHORTCUT` / `SEPARATOR`
  #   constants. Each actionable item carries a `data-command-value` (filter text).
  #
  # ## Sizes
  # `sm` · `md` · `lg` — the centered panel's max width.
  # @logical_path Actions
  class CommandComponentPreview < ViewComponent::Preview
    include UIHelper

    # A trigger button opens the palette; two groups of filterable items with a
    # separator between them. (Press ⌘K / Ctrl+K to open via the global shortcut.)
    def default
    end

    # The wide (`lg`) panel — same contract, more room for long item labels.
    def large
    end
  end
end
