# frozen_string_literal: true

module UI
  # # Popover
  #
  # A non-modal floating panel anchored to a trigger button. Behavior lives in the
  # `floating` Stimulus controller shipped alongside this component. Placement is CSS
  # anchor positioning: the panel is `position: fixed` (so its containing block is the
  # viewport), tethered to the trigger via `anchor-name`/`position-anchor`; `position-area`
  # places it and `position-try-fallbacks` keeps it on-screen. Being viewport-positioned is
  # also what lets it be promoted to the browser top layer, so a `sticky`/`backdrop-blur`
  # ancestor cannot bury it.
  #
  # ## Use when
  # - You need a small interactive overlay (a menu of actions, a filter form, details)
  #   tied to a trigger that does NOT need to block the page.
  #
  # ## Don't use when
  # - The content must block interaction until dismissed — use `dialog`/`alert_dialog`.
  # - You only need a hint describing a control — use `tooltip`.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<button>` trigger with `aria-haspopup="dialog"`,
  #   `aria-expanded` (kept in sync), and `aria-controls` to the panel; the panel is
  #   `role="dialog"` named by `label:`; Escape and outside-click close and return
  #   focus to the trigger. Non-modal — focus is NOT trapped.
  # - **You supply:** a `label:` (the panel's accessible name) and a `with_trigger`
  #   slot (the button's visible content).
  class PopoverComponent < ApplicationComponent
    renders_one :trigger

    PANEL_BASE = "z-50 w-72 rounded-md border border-border bg-surface-overlay p-4 " \
                 "text-sm text-text-body shadow-md outline-none"

    SIDES = %i[bottom top left right].freeze
    ALIGNS = %i[start center end].freeze

    # Anchor-positioning placement — `side` × `align`. Each value carries the gap margin,
    # the modern path (supports-[position-area]: `fixed` + a `position-area` cell + a
    # `position-try-fallbacks` flip to stay on-screen) and the pre-Baseline `absolute`
    # fallback offsets. `position: fixed` is what lets the panel be promoted to the top
    # layer — the top layer re-parents an element's containing block to the viewport, so
    # `absolute` offsets would tear it off its trigger (see app/javascript/overlays/
    # top_layer.js). For bottom/top, `align` edge-aligns horizontally via span-right /
    # span-left; for left/right it edge-aligns vertically via span-bottom / span-top.
    # Written out one line per placement because Tailwind only sees literal class strings.
    PLACEMENTS = {
      bottom_start: "mt-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_span-right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-0",
      bottom_center: "mt-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:left-1/2 not-supports-[position-area:bottom]:-translate-x-1/2",
      bottom_end: "mt-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:bottom_span-left] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:top-full not-supports-[position-area:bottom]:right-0",
      top_start: "mb-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_span-right] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:left-0",
      top_center: "mb-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:left-1/2 not-supports-[position-area:bottom]:-translate-x-1/2",
      top_end: "mb-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:top_span-left] supports-[position-area:bottom]:[position-try-fallbacks:flip-block] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:bottom-full not-supports-[position-area:bottom]:right-0",
      left_start: "mr-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:left_span-bottom] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:right-full not-supports-[position-area:bottom]:top-0",
      left_center: "mr-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:left] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:right-full not-supports-[position-area:bottom]:top-1/2 not-supports-[position-area:bottom]:-translate-y-1/2",
      left_end: "mr-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:left_span-top] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:right-full not-supports-[position-area:bottom]:bottom-0",
      right_start: "ml-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:right_span-bottom] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:left-full not-supports-[position-area:bottom]:top-0",
      right_center: "ml-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:right] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:left-full not-supports-[position-area:bottom]:top-1/2 not-supports-[position-area:bottom]:-translate-y-1/2",
      right_end: "ml-2 supports-[position-area:bottom]:fixed supports-[position-area:bottom]:[position-area:right_span-top] supports-[position-area:bottom]:[position-try-fallbacks:flip-inline] not-supports-[position-area:bottom]:absolute not-supports-[position-area:bottom]:left-full not-supports-[position-area:bottom]:bottom-0"
    }.freeze

    # label:         the panel's accessible name (required → aria-label on role=dialog)
    # id:            panel id (auto-generated if omitted; wired to aria-controls)
    # align:         :start | :center | :end
    # side:          :bottom | :top | :left | :right
    # trigger_class: CSS for the trigger button (default canonical .btn-secondary)
    def initialize(label:, id: nil, align: :start, side: :bottom, trigger_class: "btn-secondary", **html_attrs)
      @label         = label
      @id            = id || "popover-#{SecureRandom.hex(4)}"
      @align         = coerce_enum(:align, align, ALIGNS)
      @side          = coerce_enum(:side, side, SIDES)
      @trigger_class = trigger_class
      @extra_class   = html_attrs.delete(:class)
      @html_attrs    = html_attrs
    end

    def call
      raise ArgumentError, "UI::PopoverComponent requires a with_trigger slot" unless trigger?

      content_tag(:div, **wrapper_attrs) do
        safe_join([ trigger_button, panel ])
      end
    end

    private

    def wrapper_attrs
      {
        class: cn("relative inline-block", @extra_class),
        style: "anchor-name: --#{@id}",
        data: {
          controller: "floating",
          action: "keydown.esc->floating#close click@document->floating#closeOnClickOutside"
        }
      }.merge(@html_attrs)
    end

    def trigger_button
      content_tag(:button, trigger,
        type: "button",
        "aria-haspopup": "dialog",
        "aria-expanded": "false",
        "aria-controls": @id,
        data: { floating_target: "trigger", action: "click->floating#toggle" },
        class: @trigger_class)
    end

    def panel
      content_tag(:div, content,
        id: @id,
        role: "dialog",
        "aria-label": @label,
        tabindex: "-1",
        hidden: true,
        style: "position-anchor: --#{@id}",
        data: { floating_target: "panel" },
        class: cn(PANEL_BASE, PLACEMENTS.fetch(:"#{@side}_#{@align}")))
    end

    def coerce_enum(name, value, allowed)
      key = value.to_sym
      return key if allowed.include?(key)

      raise ArgumentError,
        "UI::Popover unknown #{name}: #{value.inspect} (allowed: #{allowed.join(", ")})"
    end
  end
end
