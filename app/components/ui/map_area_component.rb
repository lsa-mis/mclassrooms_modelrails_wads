# frozen_string_literal: true

module UI
  # # Map / Area
  #
  # An image map: an `<img usemap>` paired with a `<map>` of clickable `<area>`
  # hotspots. Image maps are a legacy mechanism — prefer overlaid links/buttons or
  # an inline SVG with `<a>` regions when you can. When you genuinely need an
  # `<area>`-based map, this component enforces the accessibility contract that
  # makes one usable.
  #
  # ## Accessibility contract
  # - **Guarantees:** the base `<img>` carries `alt:` and a `usemap` wired to the
  #   `<map name>`; every interactive `<area href>` is forced to carry a non-blank
  #   `alt` (its accessible name) — an unnamed hotspot raises rather than ship a
  #   nameless link to assistive tech (WCAG 2.4.4 / 4.1.2).
  # - **You supply:** real `alt:` for the image, and an `alt:` for every linked
  #   area. Non-interactive areas (no `href`) may omit `alt`.
  #
  # Usage:
  #   ui :map_area,
  #     src: "/map.png", alt: "Office floor plan",
  #     width: 800, height: 600,
  #     areas: [
  #       { shape: :rect,   coords: "0,0,200,150",   href: "/room/1", alt: "Room 1" },
  #       { shape: :circle, coords: "400,300,50",    href: "/room/2", alt: "Room 2" },
  #       { shape: :poly,   coords: "10,10,50,10,30,40", href: "/room/3", alt: "Room 3" }
  #     ]
  #
  # area keys:
  #   shape:   :rect | :circle | :poly | :default (required)
  #   coords:  coordinate string (required for rect/circle/poly)
  #   href:    link target (omit for non-interactive areas)
  #   alt:     accessible label — REQUIRED whenever href is present
  #   title:   tooltip text
  #   target:  link target, e.g. "_blank"
  #   rel:     link rel attribute
  class MapAreaComponent < ApplicationComponent
    WRAPPER_CLS = "relative inline-block"

    def initialize(src:, alt:, areas: [], width: nil, height: nil,
                   loading: :lazy, map_name: nil, **html_attrs)
      @src       = src
      @alt       = alt
      @areas     = areas
      @width     = width
      @height    = height
      @loading   = loading
      @map_name  = map_name || "map-#{SecureRandom.hex(4)}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:div, class: cn(WRAPPER_CLS, @extra_class), **@html_attrs) do
        safe_join([ img_tag, map_tag ])
      end
    end

    private

    def img_tag
      attrs = { src: @src, alt: @alt, usemap: "##{@map_name}", loading: @loading }
      attrs[:width]  = @width  if @width
      attrs[:height] = @height if @height
      tag.img(**attrs)
    end

    def map_tag
      content_tag(:map, name: @map_name) do
        safe_join(@areas.map { |area| area_tag(area) })
      end
    end

    def area_tag(area)
      href = area[:href]
      alt  = area[:alt]
      require_area_alt!(area) if href && alt.to_s.strip.empty?

      attrs = { shape: area.fetch(:shape, :rect).to_s }
      attrs[:alt]    = alt.to_s
      attrs[:coords] = area[:coords]  if area[:coords]
      attrs[:href]   = href           if href
      attrs[:title]  = area[:title]   if area[:title]
      attrs[:target] = area[:target]  if area[:target]
      attrs[:rel]    = area[:rel]     if area[:rel]
      tag.area(**attrs)
    end

    # An <area href> with no accessible name is an unlabeled interactive control —
    # a WCAG failure. Fail loud at the call site outside production; in production
    # we don't 500 a page over content data — the missing alt is left absent so the
    # markup is at least valid (and surfaces in an axe audit). The Rails.respond_to?
    # guard mirrors the indicator component (Rails may be defined without Rails.env
    # booted in the gem's Rails-less tests).
    def require_area_alt!(area)
      return if defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?

      raise ArgumentError,
        "UI::MapAreaComponent: area #{area[:href].inspect} has an href but no alt. " \
        "Every linked <area> needs a non-blank alt (its accessible name) for WCAG 2.4.4/4.1.2."
    end
  end
end
