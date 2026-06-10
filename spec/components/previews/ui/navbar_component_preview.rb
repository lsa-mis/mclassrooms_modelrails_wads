# frozen_string_literal: true

module UI
  # # Navbar
  #
  # A responsive nav. On a narrow viewport the links collapse behind a hamburger that discloses
  # a stacked menu (aria-expanded/controls + Escape + outside-click). Resize the Lookbook frame
  # narrow to see the mobile disclosure.
  # @logical_path Navigation
  class NavbarComponentPreview < ViewComponent::Preview
    include UIHelper

    # Brand + Dashboard/Pricing/Docs links + a Sign in action (Dashboard active).
    def basic
    end
  end
end
