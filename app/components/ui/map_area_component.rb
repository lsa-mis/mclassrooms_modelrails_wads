# frozen_string_literal: true

module UI
  # An image map: an `<img usemap>` paired with a `<map>` of clickable `<area>` hotspots.
  # Usage, options and the accessibility contract: docs/components/map_area.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
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
