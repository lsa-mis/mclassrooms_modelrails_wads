# frozen_string_literal: true

module UI
  # # Combobox
  #
  # An autocomplete select: a `role="combobox"` text input that filters a
  # `role="listbox"` of options and writes the chosen value to a hidden field for
  # form submission. Filtering and keyboard navigation live in the `combobox`
  # Stimulus controller shipped alongside this component.
  #
  # ## Use when
  # - You need a single-choice control over a long, known list where free-text
  #   filtering beats scrolling a native `<select>`.
  #
  # ## Don't use when
  # - The list is short and needs no search — use a native `select`.
  # - It's a keyboard-first launcher for *actions* (the ⌘K pattern) — use `command`.
  #
  # ## Accessibility contract (WAI-ARIA APG combobox + listbox)
  # - **Guarantees:** the input is a `role="combobox"` (`aria-expanded` /
  #   `aria-controls` / `aria-autocomplete="list"`) named by an i18n `aria-label`
  #   (override via `label:`), controlling a named `role="listbox"` of
  #   `role="option"` items. The controller tracks the highlighted option via
  #   `aria-activedescendant` (DOM focus stays on the input — ↑/↓/Home/End move the
  #   active option, Enter selects, Escape closes). The input + options carry the
  #   AAA `focus-ring`; the empty state is an i18n live region.
  # - **You supply:** `name:`, `options:` (`{ value:, label: }`), optional `value:`,
  #   `placeholder:`, `label:` (accessible name), and `size:`.
  #
  # The dropdown opens on focus — click the input to reveal the listbox.
  #
  # ## Sizes
  # `sm` · `md` · `lg` — the input height.
  #
  # ## Related
  # `select` · `command`
  # @logical_path Forms & Inputs
  class ComboboxComponentPreview < ViewComponent::Preview
    include UIHelper

    # The default md combobox. Focus the input to open the filterable listbox.
    def default
    end

    # Pre-selected value, custom `label:`, and the wide (`lg`) input.
    def preselected
    end
  end
end
