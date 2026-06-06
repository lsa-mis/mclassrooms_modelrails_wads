# frozen_string_literal: true

module UI
  # # Hover Card
  #
  # A rich, supplemental card revealed on hover **and** keyboard focus of its trigger,
  # driven by the `floating` controller's hover-intent: a short close-delay lets the
  # pointer cross the trigger→card gap so the card's interactive content stays
  # reachable and clickable. Escape closes and returns focus to the trigger.
  #
  # ## Use when
  # - A link/avatar benefits from a supplemental preview (profile, definition) whose
  #   content is ALSO reachable elsewhere (the card is an enhancement, not the only path).
  #
  # ## Don't use when
  # - The content is a primary interactive surface — use `popover` (click) or a `dialog`.
  # - It's a short text hint — use `tooltip`.
  #
  # ## Accessibility contract
  # - **Guarantees:** opens on hover AND focus; the hover-intent close-delay keeps the
  #   card reachable, so its content is clickable and Tab-reachable; Escape closes and
  #   returns focus to the trigger; `role="group"` + `aria-label` when `label:` is given.
  # - **You supply:** a `with_trigger` slot (a focusable link/button) and the card content.
  class HoverCardComponent < ApplicationComponent
    renders_one :trigger

    CARD_BASE = "z-50 w-64 rounded-lg border border-border bg-surface-overlay p-4 text-sm " \
                "text-text-body shadow-md " \
                "invisible opacity-0 transition-opacity duration-200 " \
                "group-data-[state=open]:visible group-data-[state=open]:opacity-100"

    # Placement on the `position-area` grid — 4 edges + 4 corners. Each value carries the
    # gap margin, the modern path (gated by `supports-[position-area]`: `fixed` + a
    # `position-area` value + `position-try-fallbacks` to keep it on-screen), and the
    # pre-Baseline `absolute` fallback offsets (`not-supports-`). A Tailwind class table —
    # one line per placement keeps it scannable.
    # rubocop:disable Layout/LineLength
    POSITIONS = {
      bottom:       "mt-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_center] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-1/2 not-supports-[position-area:bottom]:-translate-x-1/2",
      top:          "mb-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_center] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:left-1/2 not-supports-[position-area:bottom]:-translate-x-1/2",
      left:         "mr-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:center_left] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:right-full not-supports-[position-area:bottom]:top-1/2 not-supports-[position-area:bottom]:-translate-y-1/2",
      right:        "ml-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:center_right] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:left-full not-supports-[position-area:bottom]:top-1/2 not-supports-[position-area:bottom]:-translate-y-1/2",
      top_left:     "mb-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_left] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:left-0",
      top_right:    "mb-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:right-0",
      bottom_left:  "mt-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_left] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-0",
      bottom_right: "mt-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:right-0"
    }.freeze
    # rubocop:enable Layout/LineLength

    # id: card id; label: optional accessible name (→ role=group + aria-label);
    # side: edge :bottom | :top | :left | :right, or corner :top_left | :top_right | :bottom_left | :bottom_right
    def initialize(id: nil, label: nil, side: :bottom, **html_attrs)
      @id          = id || "hovercard-#{SecureRandom.hex(4)}"
      @label       = label
      @side        = coerce_enum(:side, side, POSITIONS)
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      raise ArgumentError, "UI::HoverCardComponent requires a with_trigger slot" unless trigger?

      content_tag(:span, **wrapper_attrs) do
        safe_join([ trigger, card ])
      end
    end

    private

    def wrapper_attrs
      {
        class: cn("group relative inline-block", @extra_class),
        style: "anchor-name: --#{@id}",
        data: {
          controller: "floating",
          action: "mouseenter->floating#hoverOpen mouseleave->floating#hoverClose " \
                   "focusin->floating#hoverOpen focusout->floating#hoverClose " \
                   "keydown.esc->floating#hoverEscape"
        }
      }.merge(@html_attrs)
    end

    def card
      attrs = {
        id: @id,
        style: "position-anchor: --#{@id}",
        data: { floating_target: "panel" },
        class: cn(CARD_BASE, POSITIONS.fetch(@side))
      }
      if @label
        attrs[:role] = "group"
        attrs["aria-label"] = @label
      end
      content_tag(:div, content, **attrs)
    end

    def coerce_enum(name, value, map)
      key = value.to_sym
      return key if map.key?(key)

      raise ArgumentError, "UI::HoverCard unknown #{name}: #{value.inspect} (allowed: #{map.keys.join(", ")})"
    end
  end
end
