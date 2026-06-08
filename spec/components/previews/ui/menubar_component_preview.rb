# frozen_string_literal: true

module UI
  # # Menubar
  #
  # An app menubar (WAI-ARIA APG). Tab to it (one stop), ←/→ between items, ↓/Enter to open a
  # submenu, ↑/↓ within, Escape to close. Submenus reuse the shared `menu` controller.
  class MenubarComponentPreview < ViewComponent::Preview
    include UIHelper

    # File / Edit / View menubar with submenus.
    def basic
    end
  end
end
