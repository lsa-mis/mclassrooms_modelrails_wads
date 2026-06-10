# frozen_string_literal: true

module UI
  # # Navigation menu
  #
  # A horizontal site-navigation bar: a **named** `<nav>` landmark whose entries are
  # links, with some opening a **disclosure** flyout (the APG navigation-menu — NOT a
  # `role="menu"` widget). Flyout triggers are real `<button>`s whose `aria-expanded`
  # is synced (and `aria-controls` points at their `id`'d panel) by the component-owned
  # `navigation-menu` controller.
  #
  # ## Accessibility contract
  # - **Guarantees:** a named `<nav>` landmark (i18n default, override via `label:`);
  #   disclosure triggers carry `aria-expanded` (synced) + `aria-controls`; the AAA
  #   `focus-ring` on every link, trigger and panel link; `aria-current="page"` on the
  #   active link; the chevron is decorative.
  # - **You supply:** items (label, optional href, optional active) and — for flyout
  #   items — the panel links via the slot block.
  # @logical_path Navigation
  class NavigationMenuComponentPreview < ViewComponent::Preview
    include UIHelper

    # A bar of links plus a disclosure flyout.
    def default
    end
  end
end
