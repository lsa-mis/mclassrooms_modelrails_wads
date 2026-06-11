# frozen_string_literal: true

module UI
  # # Card
  #
  # A presentational content container composed of optional header / content /
  # footer regions. The card itself is a neutral `<div>` and carries no document
  # structure — the heading inside (`card_title`) is the only structural piece, and
  # the CALLER owns its level via `level:`.
  #
  # ## Use when
  # - Grouping related content into a bordered, raised surface (settings panel,
  #   summary tile, media object).
  #
  # ## Don't use when
  # - The whole card should be a link/button — put a real focusable `link`/`button`
  #   inside it; never make the container `<div>` itself interactive.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA `text-text-body` on `bg-surface-raised`, a semantic
  #   `border-border` rule, and a system shadow (no raw color/shadow). The container
  #   is non-interactive and adds no ARIA role.
  # - **You supply:** the heading via `card_title` (set `level:` so it sits correctly
  #   in the page outline) and any focusable controls inside the regions.
  # @logical_path Data Display
  class CardComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Title + description in a header, with body content.
    def default
    end

    # The full composition — header, content, and a footer action bar.
    def with_footer
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — skip a heading level
    #
    # `card_title` renders a real heading, so its `level:` must follow the page
    # outline. Dropping an `<h3>` directly under an `<h1>` skips `<h2>` and breaks
    # navigation for screen-reader users. Pass the `level:` that fits where the card
    # sits (here, `level: 2` under the page's `<h1>`).
    # @label Don't · skip a heading level
    def dont_heading_misuse
    end

    # @!endgroup
  end
end
