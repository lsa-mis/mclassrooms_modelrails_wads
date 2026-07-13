# frozen_string_literal: true

module UI
  # # Tooltip
  #
  # A small text bubble describing the element it wraps. Shows on hover **and**
  # keyboard focus; the wrapper is focusable and `aria-describedby` wires the bubble
  # to it. Escape dismisses (WCAG 1.4.13) via the shared `floating` controller.
  #
  # Placement uses CSS anchor positioning: the bubble is `position: fixed` (so its
  # containing block is the viewport, letting it float free of the wrapper) and tethered
  # to the wrapper via `anchor-name`/`position-anchor`; `position-area` places it and
  # `position-try-fallbacks` auto-flips it on viewport overflow — no JS. On browsers
  # without anchor positioning (pre-Baseline 2026) it falls back to `absolute` offsets.
  #
  # ## Use when
  # - You need a short, non-interactive hint describing a single focusable trigger
  #   (an icon button, a truncated label).
  #
  # ## Don't use when
  # - The content is interactive or rich — use `hover_card`.
  # - You wrap an already-interactive control — put `aria-describedby` on that control
  #   instead (this component makes its own wrapper the focusable trigger).
  #
  # ## Accessibility contract
  # - **Guarantees:** shows on hover AND focus; `role="tooltip"` bubble wired via
  #   `aria-describedby`; Escape dismisses without moving focus; `pointer-events-none`
  #   so the bubble never traps the pointer.
  # - **You supply:** `text:` (the hint) and the trigger content (icon/word).
  class TooltipComponent < ApplicationComponent
    BUBBLE_BASE = "z-50 w-max max-w-xs rounded-md px-3 py-1.5 text-xs text-balance " \
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
    # rubocop:disable Layout/LineLength
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
    # rubocop:enable Layout/LineLength

    # Public API for the documented "describe an existing interactive control"
    # pattern (see "Do not use when"): callers build their own group/tooltip
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
      {
        # focus-ring: the wrapper is TABBABLE (tabindex below) — a focusable
        # element with no visible focus indicator fails WCAG 2.4.7 (found on
        # the pano pane's info chip, 2026-07-13; applies to every usage).
        # min-h-11: the wrapper is a TABBABLE target — the 44px AAA floor
        # applies to it like any focusable (a11y gate, 2026-07-13).
        class: cn("group/tooltip relative inline-flex min-h-11 items-center rounded-md focus-ring", @extra_class),
        style: "anchor-name: --#{@id}",
        tabindex: "0",
        "aria-describedby": @id,
        data: {
          controller: "floating",
          action: "keydown.esc->floating#dismiss mouseleave->floating#clearDismissed focusout->floating#clearDismissed"
        }
      }.merge(@html_attrs)
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
