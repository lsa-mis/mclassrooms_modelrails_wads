# frozen_string_literal: true

module UI
  # A responsive embedded-frame wrapper (`<iframe>`), optionally aspect-ratio constrained, with lazy loading and sandboxing on by default.
  # Usage, options and the accessibility contract: docs/components/iframe.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class IframeComponent < ApplicationComponent
    BASE = "w-full border-0"

    LOADING_MODES = %i[lazy eager auto].freeze

    def initialize(src:, title:, loading: :lazy, sandbox: true,
                   aspect: nil, width: nil, height: nil, **html_attrs)
      raise ArgumentError, "UI::IframeComponent requires a non-blank title: (the iframe's accessible name)" if title.to_s.strip.empty?

      @src     = src
      @title   = title
      @loading = LOADING_MODES.include?(loading.to_sym) ? loading.to_sym : :lazy
      @sandbox = sandbox
      @aspect  = aspect
      @width   = width
      @height  = height
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      if @aspect
        content_tag(:div, style: "aspect-ratio: #{@aspect}", class: "w-full overflow-hidden") do
          iframe_tag
        end
      else
        iframe_tag
      end
    end

    private

    def iframe_tag
      attrs = {
        src: @src,
        title: @title,
        loading: @loading,
        class: cn(BASE, (@aspect ? "h-full" : nil), @extra_class)
      }
      attrs[:sandbox] = sandbox_value if @sandbox != false
      attrs[:width]   = @width  if @width
      attrs[:height]  = @height if @height
      tag.iframe(**attrs, **@html_attrs)
    end

    def sandbox_value
      return "allow-scripts allow-same-origin allow-forms allow-popups" if @sandbox == true

      @sandbox
    end
  end
end
