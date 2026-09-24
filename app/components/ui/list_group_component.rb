# frozen_string_literal: true

module UI
  # A styled vertical list of rows — static items, navigation links, or actions.
  # Usage, options and the accessibility contract: docs/components/list_group.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class ListGroupComponent < ApplicationComponent
    BASE = "divide-y divide-border overflow-hidden rounded-lg border border-border bg-surface-raised"

    def initialize(**html_attrs)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:ul, content, **list_attrs)
    end

    private

    # Tailwind's preflight sets `list-style: none` on `ul`, and Safari/VoiceOver
    # drops the implicit list role once the marker is gone — so `role="list"` is
    # load-bearing, not decoration, and no axe rule covers it.
    #
    # Keys are stringified before the caller's attrs are merged: `content_tag`
    # does NOT de-duplicate a symbol `:role` against a string `"role"`, so the
    # naive spelling emits BOTH and lets the browser pick. The caller merges last
    # because a list that is really a navigation is the caller's call to make.
    def list_attrs
      attrs = { "role" => "list", "class" => cn(BASE, @extra_class) }
      @html_attrs.each { |key, value| attrs[key.to_s] = value }
      attrs
    end
  end
end
