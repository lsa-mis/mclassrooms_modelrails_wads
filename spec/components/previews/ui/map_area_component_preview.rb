# frozen_string_literal: true

module UI
  # # Map / Area
  #
  # An image map: an `<img usemap>` + a `<map>` of clickable `<area>` hotspots.
  # Image maps are a legacy mechanism — prefer overlaid links/buttons or an inline
  # SVG with `<a>` regions when you can. When you genuinely need `<area>` hotspots,
  # this component enforces the contract that makes one accessible.
  #
  # ## Use when
  # - You must map clickable regions onto a single raster image (floor plan, world
  #   map, diagram) and richer markup isn't an option.
  #
  # ## Don't use when
  # - The regions could be real overlaid links/buttons or SVG `<a>` paths — those
  #   scale, restyle, and label far better than `<area>` coordinates.
  #
  # ## Accessibility contract
  # - **Guarantees:** the `<img>` carries `alt:` and a `usemap` wired to the
  #   `<map name>`; every interactive `<area href>` is forced to carry a non-blank
  #   `alt` (its accessible name) — an unnamed hotspot raises (WCAG 2.4.4 / 4.1.2).
  # - **You supply:** real `alt:` for the image and an `alt:` for every linked area.
  # @logical_path Media
  class MapAreaComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # An image with two labeled, clickable hotspots.
    def default
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — a hotspot with no accessible name
    #
    # An `<area href>` with no `alt` is an interactive control with no name: screen
    # readers announce a bare, unusable link (WCAG 2.4.4 / 4.1.2). The component
    # raises rather than emit one — every linked area must supply an `alt`.
    # @label Don't · area without alt
    def dont_area_no_alt
    end

    # @!endgroup
  end
end
