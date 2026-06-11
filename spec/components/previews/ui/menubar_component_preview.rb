# frozen_string_literal: true

module UI
  # # Menubar
  #
  # An app menubar (WAI-ARIA APG). Tab to it (one stop), ←/→ between items, ↓/Enter to open a
  # submenu, ↑/↓ within, Escape to close. Submenus reuse the shared `menu` controller.
  #
  # ## Use when
  # - A persistent application menu bar (File / Edit / View) exposing grouped commands.
  #
  # ## Don't use when
  # - Actions launch from a single button — use `dropdown_menu`.
  # - Actions open from right-click on a region — use `context_menu`.
  #
  # ## Accessibility contract
  # - **Guarantees:** WAI-ARIA APG menubar — one Tab stop, roving tabindex, ←/→ moves
  #   between top-level items (following an open submenu), ↓/Enter opens a submenu
  #   (the shared `menu` controller: ↑/↓, type-ahead, Escape closes and restores focus).
  # - **You supply:** `label:` (required — the bar's accessible name) and the items.
  #
  # ## Related
  # `dropdown_menu` · `context_menu`
  # @logical_path Overlays
  class MenubarComponentPreview < ViewComponent::Preview
    include UIHelper

    # File / Edit / View menubar with submenus.
    def basic
    end
  end
end
