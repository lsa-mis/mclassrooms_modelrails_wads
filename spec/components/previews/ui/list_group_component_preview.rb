# frozen_string_literal: true

module UI
  # # ListGroup
  #
  # A styled vertical list of rows — static items, navigation links, or actions.
  # Renders a real `<ul>` of `<li>`; navigable rows are an `<a>` inside `<li>`.
  #
  # ## Use when
  # - You have a short, related set of rows: a settings menu, a sidebar of links,
  #   a list of records, a stack of choices.
  #
  # ## Don't use when
  # - The rows are tabular data with columns — use a `data_table`.
  # - You need `<div>` rows with click handlers — that breaks list semantics and
  #   keyboard access. Use real `<a>`/`<button>` rows (see the Don't below).
  #
  # ## Accessibility contract
  # - **Guarantees:** a semantic `<ul>` on a token surface; link rows are real
  #   `<a>` elements inside `<li>` with the `focus-ring` utility; the active link
  #   carries `aria-current="page"`; static rows are never made focusable.
  # - **You supply:** the rows via `list_group_item` (text or block content),
  #   `href:` for navigable rows, and `active: true` on the current page.
  # @logical_path Data Display
  class ListGroupComponentPreview < ViewComponent::Preview
    include UIHelper

    # Static rows — a plain <ul> of <li>, with a muted row for de-emphasis.
    def default
    end

    # Navigable rows — each is an <a> inside its <li>, with the current page
    # marked `active: true` (renders `aria-current="page"`).
    def links
    end

    # ## Don't — non-semantic <div> rows
    #
    # Building rows as <div>s with click handlers is invisible to assistive tech
    # and unreachable by keyboard. Use a real `<a>` (href:) or `<button>` row so
    # the list stays a `<ul>`/`<li>` and every interactive row is focusable.
    # @label Don't · div rows
    def dont_div_rows
    end
  end
end
