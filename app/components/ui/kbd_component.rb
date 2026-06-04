# frozen_string_literal: true

module UI
  # # Kbd
  #
  # A small inline chip representing a keyboard key or shortcut, rendered as a
  # semantic `<kbd>`. Purely presentational and non-interactive.
  #
  # ## Use when
  # - Documenting a keyboard shortcut inline ("Press ⌘K to search") or inside a
  #   menu item / tooltip.
  #
  # ## Don't use when
  # - The text isn't a keyboard key — `<kbd>` misrepresents the semantics to
  #   assistive tech. Use plain text or a `badge` for non-key labels.
  # - You need it to be clickable — it is `pointer-events-none` by contract.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA-contrast text on `bg-surface-sunken`, non-interactive
  #   (`pointer-events-none` + `select-none`), and inline-SVG key icons auto-sized
  #   to match the text.
  # - **You supply:** the key text via the positional arg, `label:`, or slot content.
  class KbdComponent < ApplicationComponent
    BASE = "pointer-events-none inline-flex h-5 w-fit min-w-5 items-center justify-center gap-1 " \
           "rounded-sm bg-surface-sunken px-1 font-sans text-xs font-medium text-text-muted select-none " \
           "[&_svg:not([class*='size-'])]:size-3"

    def initialize(key = nil, **html_attrs)
      @key = key || html_attrs.delete(:label)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:kbd, content.presence || @key,
        class: cn(BASE, @extra_class),
        **@html_attrs)
    end
  end
end
