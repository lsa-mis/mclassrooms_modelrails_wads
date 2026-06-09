# frozen_string_literal: true

module UI
  # # Iframe
  #
  # A responsive embedded-frame wrapper (`<iframe>`), optionally aspect-ratio
  # constrained, with lazy loading and sandboxing on by default.
  #
  # ## Use when
  # - Embedding external content (a map, video, document, or third-party widget)
  #   and you want a responsive, sandboxed frame with an explicit accessible name.
  #
  # ## Don't use when
  # - The content is first-party imagery or video you control — use `image` or a
  #   native `<video>`; an iframe is for cross-document/embedded content.
  #
  # ## Accessibility contract
  # - **Guarantees:** `title:` is REQUIRED and must be non-blank — every iframe
  #   carries an accessible name (a title-less iframe is a hard WCAG failure, and
  #   unlike an image there is no "decorative" exception). An invalid `loading:`
  #   falls back to `:lazy`.
  # - **You supply:** a real `title:` describing the embedded content (e.g.
  #   "Map of the office location", "Product demo video").
  #
  # ## Parameters
  # - `src:`     URL to embed (required)
  # - `title:`   accessible name describing the iframe content (required, non-blank)
  # - `loading:` :lazy (default) | :eager | :auto
  # - `sandbox:` space-separated token string, or `true` for strict defaults;
  #              pass `false` to disable sandboxing entirely (not recommended)
  # - `aspect:`  CSS aspect-ratio value, e.g. "16/9", "4/3" (wraps in a div);
  #              omit if you set explicit width/height
  # - `width:`/`height:` explicit pixel dimensions (applied to the `<iframe>`)
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
