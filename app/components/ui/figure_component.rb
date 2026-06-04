# frozen_string_literal: true

module UI
  # # Figure
  #
  # A semantic `<figure>` that wraps content (an image, a code block, a chart) with an
  # optional `<figcaption>`. The caption supplements the content; it does not replace
  # the content's own accessible name.
  #
  # ## Use when
  # - You have referenced/standalone content that benefits from a visible caption
  #   (a captioned image, a diagram, a quoted block).
  #
  # ## Don't use when
  # - You're relying on the caption to describe an image that has no `alt`. The
  #   figcaption is a supplement, not a substitute — the image still needs its own
  #   `alt` (use `alt: ""` only if it is genuinely decorative).
  #
  # ## Accessibility contract
  # - **Guarantees:** semantic `<figure>`/`<figcaption>` association; the caption is
  #   rendered only when provided. The caption uses `text-text-muted`, which in this
  #   token system is the SAME neutral as body text (AAA 7:1) — de-emphasis is by
  #   size/weight, not lightness.
  # - **You supply:** real `alt` on any inner image (the figcaption does not replace it).
  #
  # ## Parameters
  # - `caption:` text shown in `<figcaption>` (optional; omit to render none)
  # - `caption_class:` override/extend the figcaption classes
  class FigureComponent < ApplicationComponent
    CAPTION = "mt-2 text-sm text-text-muted"

    def initialize(caption: nil, caption_class: nil, **html_attrs)
      @caption       = caption
      @caption_class = caption_class
      @extra_class   = html_attrs.delete(:class)
      @html_attrs    = html_attrs
    end

    def call
      content_tag(:figure, class: @extra_class, **@html_attrs) do
        concat content
        concat content_tag(:figcaption, @caption,
          class: cn(CAPTION, @caption_class)) if @caption
      end
    end
  end
end
