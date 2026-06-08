# frozen_string_literal: true

module UI
  # # Tabs
  #
  # APG tabs (automatic activation). Tab to the active tab, ←/→ to move + reveal panels,
  # Home/End to jump; the disabled tab is skipped. Tab again to enter the active panel.
  class TabsComponentPreview < ViewComponent::Preview
    include UIHelper

    # Profile / Password / Notifications (Notifications disabled).
    def basic
    end
  end
end
