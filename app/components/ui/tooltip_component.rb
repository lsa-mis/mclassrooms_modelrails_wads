# frozen_string_literal: true

module UI
  # A small text bubble describing the element it wraps.
  # Usage, options and the accessibility contract: docs/components/tooltip.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class TooltipComponent < ApplicationComponent
    BUBBLE_BASE = "z-50 w-max max-w-[min(20rem,calc(100vw-2rem))] rounded-md px-3 py-1.5 text-xs text-balance " \
                  "bg-text-heading text-surface-raised whitespace-normal " \
                  "pointer-events-none opacity-0 transition-opacity duration-200 " \
                  "group-hover/tooltip:opacity-100 group-focus-within/tooltip:opacity-100 " \
                  "group-data-[dismissed]/tooltip:opacity-0!"

    # Placement on the `position-area` grid — 4 edges + 4 corners. Each value carries the
    # gap margin, the modern path (gated by `supports-[position-area]`: `fixed` + a
    # `position-area` value + `position-try-fallbacks` to keep it on-screen), and the
    # pre-Baseline `absolute` fallback offsets (`not-supports-`). Corners fall back to a
    # corner-aligned edge on browsers without anchor positioning. A Tailwind class table —
    # one line per placement keeps it scannable.
    POSITIONS = {
      top:          "mb-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_center] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:left-1/2 not-supports-[position-area:bottom]:-translate-x-1/2",
      bottom:       "mt-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_center] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-1/2 not-supports-[position-area:bottom]:-translate-x-1/2",
      left:         "mr-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:center_left] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:right-full not-supports-[position-area:bottom]:top-1/2 not-supports-[position-area:bottom]:-translate-y-1/2",
      right:        "ml-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:center_right] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:left-full not-supports-[position-area:bottom]:top-1/2 not-supports-[position-area:bottom]:-translate-y-1/2",
      top_left:     "mb-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_left] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:left-0",
      top_right:    "mb-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:right-0",
      bottom_left:  "mt-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_left] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-0",
      bottom_right: "mt-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:right-0"
    }.freeze

    # Public API for the documented "describe an existing interactive control"
    # pattern (see "Don't use when"): callers build their own group/tooltip
    # wrapper + aria-describedby and reuse the bubble exactly.
    def self.bubble_classes(side: :top)
      "#{BUBBLE_BASE} #{POSITIONS.fetch(side)}"
    end

    # text: the hint (the bubble's content); id: bubble id (→ aria-describedby + anchor);
    # side: edge :top | :bottom | :left | :right, or corner :top_left | :top_right |
    #       :bottom_left | :bottom_right
    def initialize(text:, id: nil, side: :top, **html_attrs)
      @text        = text
      @id          = id || "tooltip-#{SecureRandom.hex(4)}"
      @side        = coerce_enum(:side, side, POSITIONS)
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:span, **wrapper_attrs) do
        safe_join([ content, bubble ])
      end
    end

    private

    def wrapper_attrs
      # merge_html_attrs, not a flat merge: a caller's `data:` would otherwise
      # replace this hash wholesale and take data-controller with it.
      merge_html_attrs({
        class: cn("group/tooltip relative inline-flex min-h-input items-center rounded-md focus-ring", @extra_class),
        style: "anchor-name: --#{@id}",
        tabindex: "0",
        "aria-describedby": @id,
        data: {
          controller: "floating",
          action: "keydown.esc->floating#dismiss mouseleave->floating#clearDismissed focusout->floating#clearDismissed"
        }
      }, @html_attrs)
    end

    def bubble
      content_tag(:span, @text,
        id: @id,
        role: "tooltip",
        style: "position-anchor: --#{@id}",
        class: cn(BUBBLE_BASE, POSITIONS.fetch(@side)))
    end

    def coerce_enum(name, value, map)
      key = value.to_sym
      return key if map.key?(key)

      raise ArgumentError, "UI::Tooltip unknown #{name}: #{value.inspect} (allowed: #{map.keys.join(", ")})"
    end
  end
end
