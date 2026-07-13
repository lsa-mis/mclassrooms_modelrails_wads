# frozen_string_literal: true

module UI
  class GalleryComponent < ApplicationComponent
    # Responsive image grid. With lightbox: true (default) each cell is a focusable
    # <button> that opens a single shared native <dialog> (the `modal` controller —
    # focus-trap/escape/restore for free). The `gallery` controller swaps the dialog
    # image's src/alt before `modal#open` runs.
    #
    # Usage:
    #   ui :gallery, cols: 3 do |g|
    #     g.with_image(src: "/img/a.jpg", alt: "Photo A")
    #     g.with_image(src: "/img/b.jpg", alt: "The coast", caption: "The coast")
    #   end

    GRID_BASE = "grid gap-2"
    GRID_COLS = {
      1 => "grid-cols-1", 2 => "grid-cols-2", 3 => "grid-cols-3",
      4 => "grid-cols-4", 5 => "grid-cols-5", 6 => "grid-cols-6"
    }.freeze

    TRIGGER_CLS = "group relative block w-full cursor-zoom-in overflow-hidden rounded-md focus-ring"
    IMG_CLS     = "h-full w-full object-cover transition-transform duration-300 " \
                  "group-hover:scale-105 motion-reduce:transition-none"
    # Caption sits on a solid tinted surface (AAA), not white text over a gradient image.
    CAP_CLS     = "absolute inset-x-0 bottom-0 bg-surface-overlay/95 px-3 py-2 text-sm text-text-body " \
                  "opacity-0 transition-opacity group-hover:opacity-100 motion-reduce:transition-none"

    DIALOG_CLS  = "m-auto bg-transparent backdrop:bg-black/80 p-4"
    # No `scale-95` rest class — see UI::DialogComponent::PANEL (TW4 scale:
    # composes with the controller's inline transform; panels rested at 95%).
    PANEL_CLS   = "relative opacity-0"
    LIGHTBOX_IMG_CLS = "max-h-[90vh] max-w-[90vw] rounded-md object-contain"
    CLOSE_CLS   = "absolute -top-2 -right-2 inline-flex size-11 items-center justify-center " \
                  "rounded-full bg-surface-overlay border border-border shadow-sm focus-ring"

    renders_many :images, "UI::GalleryComponent::ImageComponent"

    # cols:      grid columns (1–6, default 3)
    # lightbox:  enable click/keyboard-to-enlarge (default true)
    # aspect:    Tailwind aspect class per cell (default "aspect-square")
    def initialize(cols: 3, lightbox: true, aspect: "aspect-square", **html_attrs)
      @cols        = cols.to_i.clamp(1, 6)
      @lightbox    = lightbox
      @aspect      = aspect
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      validate_alts! if @lightbox

      grid_attrs = { class: cn(GRID_BASE, GRID_COLS[@cols], @extra_class) }
      grid_attrs[:data] = { controller: "gallery modal" } if @lightbox
      grid_attrs.merge!(@html_attrs)

      content_tag(:div, **grid_attrs) do
        body = safe_join(images.map { |img| cell(img) })
        @lightbox ? safe_join([ body, lightbox_dialog ]) : body
      end
    end

    private

    # An enlargeable image is not decorative — require a non-blank alt (fail loud).
    def validate_alts!
      images.each do |img|
        next if img.alt.present?

        raise ArgumentError, "gallery image #{img.src.inspect} needs a non-blank alt: when lightbox is on " \
                             "(pass lightbox: false for a decorative grid)"
      end
    end

    def cell(img)
      return plain_cell(img) unless @lightbox

      content_tag(:button, type: "button",
        class: cn(TRIGGER_CLS, @aspect),
        "aria-label": t("ui.gallery.enlarge", alt: img.alt, default: "Enlarge %{alt}"),
        data: { action: "gallery#open modal#open",
                gallery_src_param: img.src, gallery_alt_param: img.alt }) do
        caption_wrap(img)
      end
    end

    def plain_cell(img)
      content_tag(:figure, class: cn(TRIGGER_CLS.sub("cursor-zoom-in", "").sub("focus-ring", ""), @aspect)) do
        caption_wrap(img)
      end
    end

    def caption_wrap(img)
      inner = [ img ]
      inner << content_tag(:figcaption, img.caption, class: CAP_CLS) if img.caption
      safe_join(inner)
    end

    def lightbox_dialog
      content_tag(:dialog, class: DIALOG_CLS, data: { modal_target: "dialog" }) do
        content_tag(:div, class: PANEL_CLS, data: { modal_target: "panel" }) do
          safe_join([
            tag.img(class: LIGHTBOX_IMG_CLS, alt: "", data: { gallery_target: "image" }),
            close_button
          ])
        end
      end
    end

    def close_button
      content_tag(:button, close_icon, type: "button",
        "aria-label": t("ui.gallery.close", default: "Close"),
        class: CLOSE_CLS, data: { action: "click->modal#close" })
    end

    def close_icon
      raw('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" ' \
          'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' \
          '<path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>')
    end

    class ImageComponent < ApplicationComponent
      attr_reader :src, :alt, :caption

      def initialize(src:, alt: "", caption: nil, **html_attrs)
        @src     = src
        @alt     = alt
        @caption = caption
        @html_attrs = html_attrs
      end

      def call
        tag.img(src: @src, alt: @alt, class: GalleryComponent::IMG_CLS, loading: "lazy", **@html_attrs)
      end
    end
  end
end
