# frozen_string_literal: true

module UI
  # Constrains child content to a fixed aspect ratio using the CSS `aspect-ratio` property.
  # Usage, options and the accessibility contract: docs/components/aspect_ratio.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class AspectRatioComponent < ApplicationComponent
    def initialize(ratio: 1, **html_attrs)
      @ratio = ratio
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, content,
        style: "aspect-ratio: #{@ratio}",
        class: cn("overflow-hidden", @extra_class),
        **@html_attrs)
    end
  end
end
