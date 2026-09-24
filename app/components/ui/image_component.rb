# frozen_string_literal: true

module UI
  # A responsive `<img>` wrapper that enforces an `alt` decision at the call site and supports lazy loading, `srcset`/`sizes`, and intrinsic dimensions.
  # Usage, options and the accessibility contract: docs/components/image.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class ImageComponent < ApplicationComponent
    BASE = "max-w-full"

    LOADING_MODES = %i[lazy eager auto].freeze

    def initialize(src:, alt:, srcset: nil, sizes: nil, loading: :lazy,
                   width: nil, height: nil, **html_attrs)
      @src     = src
      @alt     = alt
      @srcset  = srcset
      @sizes   = sizes
      @loading = LOADING_MODES.include?(loading.to_sym) ? loading.to_sym : :lazy
      @width   = width
      @height  = height
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      attrs = { src: @src, alt: @alt, loading: @loading,
                class: cn(BASE, @extra_class) }
      attrs[:srcset]  = @srcset  if @srcset
      attrs[:sizes]   = @sizes   if @sizes
      attrs[:width]   = @width   if @width
      attrs[:height]  = @height  if @height
      tag.img(**attrs, **@html_attrs)
    end
  end
end
