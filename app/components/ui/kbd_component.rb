# frozen_string_literal: true

module UI
  # A small inline chip representing a keyboard key or shortcut, rendered as a semantic `<kbd>`.
  # Usage, options and the accessibility contract: docs/components/kbd.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
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
