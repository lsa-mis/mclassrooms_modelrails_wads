# frozen_string_literal: true

module UI
  # A semantic `<figure>` that wraps content (an image, a code block, a chart) with an optional `<figcaption>`.
  # Usage, options and the accessibility contract: docs/components/figure.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
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
