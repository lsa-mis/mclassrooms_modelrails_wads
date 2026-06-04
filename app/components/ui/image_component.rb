# frozen_string_literal: true

module UI
  # # Image
  #
  # A responsive `<img>` wrapper that enforces an `alt` decision at the call site and
  # supports lazy loading, `srcset`/`sizes`, and intrinsic dimensions.
  #
  # ## Use when
  # - You're rendering content imagery and want lazy-loading + responsive sources
  #   with the accessibility decision (alt text vs. decorative) made explicitly.
  #
  # ## Don't use when
  # - The image is an icon inside a button/link — there the accessible name comes
  #   from the control, and an inline SVG/icon helper is the better fit.
  #
  # ## Accessibility contract
  # - **Guarantees:** `alt:` is REQUIRED, forcing an explicit decision at every call
  #   site; an invalid `loading:` falls back to `:lazy`.
  # - **You supply:** real `alt:` text for meaningful images, or `alt: ""` (the
  #   correct decorative signal) for purely decorative ones. `alt` is NOT a caption —
  #   keep it a terse equivalent; use `figure` for captions.
  #
  # ## Parameters
  # - `src:` image URL (required)
  # - `alt:` alternative text (required; `""` marks the image decorative)
  # - `srcset:` responsive set, e.g. "img-sm.jpg 640w, img-lg.jpg 1280w"
  # - `sizes:` media conditions, e.g. "(max-width: 640px) 100vw, 50vw"
  # - `loading:` :lazy (default) | :eager | :auto
  # - `width:`/`height:` native dimensions (prevents layout shift)
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
