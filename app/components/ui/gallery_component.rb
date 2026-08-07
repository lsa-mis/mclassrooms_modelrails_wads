# frozen_string_literal: true

module UI
  class GalleryComponent < ApplicationComponent
    # Responsive image grid. With lightbox: true (default) each cell is a focusable
    # <button> that opens a single shared native <dialog> (the `modal` controller —
    # focus-trap/escape/restore for free). The `gallery` controller swaps the dialog
    # image's src/alt/caption before `modal#open` runs, and — with more than one
    # image — the dialog gains prev/next buttons and a counter bar
    # (see `LightboxComponent`, standalone-renderable for bespoke consumers).
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
        body = safe_join(images.each_with_index.map { |img, i| cell(img, i) })
        @lightbox ? safe_join([ body, render(LightboxComponent.new(count: images.size)) ]) : body
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

    def cell(img, idx)
      return plain_cell(img) unless @lightbox

      content_tag(:button, type: "button",
        class: cn(TRIGGER_CLS, @aspect),
        "aria-label": t("ui.gallery.enlarge", alt: img.alt, default: "Enlarge %{alt}"),
        data: { action: "gallery#open modal#open",
                gallery_index_param: idx,
                gallery_src_param: img.full_src || img.src,
                gallery_alt_param: img.alt,
                gallery_caption_param: img.caption }) do
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

    # Standalone-renderable lightbox: the gallery grid renders it automatically,
    # and bespoke consumers (e.g. a media stage) can render it directly next to
    # their own triggers. Requires `gallery modal` controllers on a shared
    # ancestor. Nav renders only when count > 1.
    class LightboxComponent < ApplicationComponent
      NAV_CLS = "absolute top-1/2 -translate-y-1/2 inline-flex size-11 items-center justify-center " \
                "rounded-full bg-surface-overlay border border-border shadow-sm focus-ring"
      BAR_CLS = "mt-1 flex items-center justify-between gap-4 rounded-b-md bg-surface-overlay px-3 py-2"
      CLOSE_CLS = "absolute -top-2 -right-2 inline-flex size-11 items-center justify-center " \
                  "rounded-full bg-surface-overlay border border-border shadow-sm focus-ring"

      def initialize(count:, label: nil)
        @count = count
        @label = label
      end

      def call
        content_tag(:dialog, class: GalleryComponent::DIALOG_CLS,
          "aria-label": @label,
          data: { modal_target: "dialog",
                  action: "keydown.left->gallery#prev keydown.right->gallery#next" }) do
          content_tag(:div, class: GalleryComponent::PANEL_CLS, data: { modal_target: "panel" }) do
            safe_join([
              tag.img(class: GalleryComponent::LIGHTBOX_IMG_CLS, alt: "", data: { gallery_target: "image" }),
              (nav_button(:prev) if @count > 1),
              (nav_button(:next) if @count > 1),
              close_button,
              (counter_bar if @count > 1)
            ].compact)
          end
        end
      end

      private

      def nav_button(dir)
        side = dir == :prev ? "-left-3" : "-right-3"
        content_tag(:button, arrow_icon(dir), type: "button",
          "aria-label": t("ui.gallery.#{dir}", default: dir == :prev ? "Previous image" : "Next image"),
          class: cn(NAV_CLS, side), data: { action: "click->gallery##{dir}" })
      end

      def counter_bar
        content_tag(:div, class: BAR_CLS) do
          safe_join([
            content_tag(:span, "", class: "text-sm text-text-body min-w-0", data: { gallery_target: "caption" }),
            content_tag(:span, "", class: "text-xs text-text-body tabular-nums shrink-0",
              aria: { hidden: true }, data: { gallery_target: "count" })
          ])
        end
      end

      def close_button
        content_tag(:button, close_icon, type: "button",
          "aria-label": t("ui.gallery.close", default: "Close"),
          class: CLOSE_CLS, data: { action: "click->modal#close" })
      end

      def arrow_icon(dir)
        path = dir == :prev ? "m15 18-6-6 6-6" : "m9 18 6-6-6-6"
        raw(%(<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="#{path}"/></svg>))
      end

      def close_icon
        raw('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" ' \
            'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' \
            '<path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>')
      end
    end

    class ImageComponent < ApplicationComponent
      attr_reader :src, :alt, :caption, :full_src

      # full_src: optional larger rendition for the lightbox swap — the cell
      # <img> keeps `src`, so a small grid thumb is never upscaled full-screen.
      def initialize(src:, alt: "", caption: nil, full_src: nil, **html_attrs)
        @src      = src
        @alt      = alt
        @caption  = caption
        @full_src = full_src
        @html_attrs = html_attrs
      end

      def call
        tag.img(src: @src, alt: @alt, class: GalleryComponent::IMG_CLS, loading: "lazy", **@html_attrs)
      end
    end
  end
end
