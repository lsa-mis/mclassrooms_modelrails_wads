# frozen_string_literal: true

module UI
  # # Footer
  #
  # A page/site footer — the `<footer>` contentinfo landmark with optional link
  # columns (heading + real `<ul>`/`<a>`), an optional block-content area, and an
  # optional copyright row below a divider.
  #
  # ## Use when
  # - Closing a page with site-wide navigation (product / company / legal columns),
  #   social/legal links, and a copyright line.
  #
  # ## Don't use when
  # - You only need an inline list of links inside an article — that isn't the page's
  #   contentinfo landmark. Use a plain `<ul>`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a `<footer>` contentinfo landmark; each column is a heading +
  #   `<ul>`/`<li>`/`<a>`; links carry the `focus-ring` utility (visible AAA focus
  #   outline); AAA-contrast text on `bg-surface-raised`.
  # - **You supply:** `columns:` (`[{ title:, links: [{ label:, href: }] }]`),
  #   `copyright:`, optional block content, and `label:` (i18n) to name the landmark
  #   when a page has more than one footer. Every link needs a readable `label:` (its
  #   accessible name) and an `href:`.
  # @logical_path Navigation
  class FooterComponentPreview < ViewComponent::Preview
    include UIHelper

    # Full footer — link columns plus a copyright row.
    def default
    end

    # Just a copyright / legal line — no columns.
    def minimal
    end

    # ## Don't — non-semantic link rows
    #
    # Flowing links inside `<div>`s (or links with no `href`/accessible name) aren't a
    # navigable list to assistive tech. Pass `columns:` so each group renders a real
    # heading + `<ul>`/`<li>`/`<a>` with the focus-ring.
    # @label Don't · div link rows
    def dont_div_links
    end
  end
end
