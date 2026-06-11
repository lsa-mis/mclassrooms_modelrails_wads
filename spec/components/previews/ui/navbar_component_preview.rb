# frozen_string_literal: true

module UI
  # # Navbar
  #
  # A responsive nav. On a narrow viewport the links collapse behind a hamburger that discloses
  # a stacked menu (aria-expanded/controls + Escape + outside-click). Resize the Lookbook frame
  # narrow to see the mobile disclosure.
  #
  # ## Use when
  # - The site's primary top navigation, responsive out of the box.
  #
  # ## Don't use when
  # - You need a collapsible application rail — use `sidebar`.
  # - The links belong at the bottom on mobile — use `bottom_nav`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `<nav>` landmark; on narrow viewports the links collapse
  #   behind a hamburger disclosure (`aria-expanded`/`aria-controls`, Escape and
  #   outside-click close, focus returns to the trigger).
  # - **You supply:** the brand slot and the link items.
  # @logical_path Navigation
  class NavbarComponentPreview < ViewComponent::Preview
    include UIHelper

    # Brand + Dashboard/Pricing/Docs links + a Sign in action (Dashboard active).
    def basic
    end
  end
end
