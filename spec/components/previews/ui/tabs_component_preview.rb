# frozen_string_literal: true

module UI
  # # Tabs
  #
  # APG tabs (automatic activation). Tab to the active tab, ←/→ to move + reveal panels,
  # Home/End to jump; the disabled tab is skipped. Tab again to enter the active panel.
  #
  # ## Use when
  # - Switching between a few in-page panels where one is visible at a time.
  #
  # ## Don't use when
  # - The destinations are different pages — use `navbar` or plain links.
  # - You need a hierarchy trail — use `breadcrumb`.
  #
  # ## Accessibility contract
  # - **Guarantees:** APG tabs with automatic activation — `role="tablist"/"tab"/"tabpanel"`
  #   wiring, roving tabindex (one Tab stop), ←/→ moves + reveals, Home/End jumps,
  #   disabled tabs are skipped, `aria-selected` stays in sync.
  # - **You supply:** tab labels and panel content.
  # @logical_path Navigation
  class TabsComponentPreview < ViewComponent::Preview
    include UIHelper

    # Profile / Password / Notifications (Notifications disabled).
    def basic
    end
  end
end
