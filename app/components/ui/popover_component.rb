# frozen_string_literal: true

module UI
  # A non-modal floating panel anchored to a trigger button.
  # Usage, options and the accessibility contract: docs/components/popover.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class PopoverComponent < ApplicationComponent
    renders_one :trigger

    # The trigger's accessibility floor — always applied, never replaceable. `trigger_class:`
    # is merged OVER this rather than replacing it: a caller restyling the trigger was
    # otherwise able to delete the focus indicator (WCAG 2.4.11) and the 44px target-size
    # floor (2.5.5 AAA) from the one element this component guarantees is "a real <button>".
    # Utilities rather than `.btn-touch-target`, so they sit in Tailwind's utilities layer
    # and merge predictably instead of racing a component class on source order.
    TRIGGER_BASE = "focus-ring min-h-input"

    PANEL_BASE = "z-50 w-72 max-w-[calc(100vw-2rem)] rounded-md border border-border bg-surface-overlay p-4 " \
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
    # trigger_class: CSS ADDED to the trigger's accessibility floor (TRIGGER_BASE);
    #                defaults to the canonical .btn-secondary. Your classes are merged
    #                over the floor, so the focus ring and target size cannot be lost.
    # trigger_attrs: attributes for the trigger BUTTON (html_attrs go to the wrapper).
    #                Merged UNDER the component's own contract, so `type`,
    #                `aria-haspopup`/`expanded`/`controls` and the Stimulus wiring can
    #                never be overwritten — a caller marking the trigger as the current
    #                choice in a group cannot also lie about its expanded state.
    def initialize(label:, id: nil, align: :start, side: :bottom, trigger_class: "btn-secondary",
      trigger_attrs: {}, **html_attrs)
      @label         = label
      @id            = id || "popover-#{SecureRandom.hex(4)}"
      @align         = coerce_enum(:align, align, ALIGNS)
      @side          = coerce_enum(:side, side, SIDES)
      @trigger_class = trigger_class
      @trigger_attrs = trigger_attrs
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

    # merge_html_attrs, not a flat merge: a caller's `data:` would otherwise replace
    # this hash wholesale and take data-controller with it, so the popover would
    # silently never open. Same bug #204 fixed for `trigger_attrs:`, one site over.
    def wrapper_attrs
      merge_html_attrs({
        class: cn("relative inline-block", @extra_class),
        style: "anchor-name: --#{@id}",
        data: {
          controller: "floating",
          action: "keydown.esc->floating#close click@document->floating#closeOnClickOutside"
        }
      }, @html_attrs)
    end

    def trigger_button
      content_tag(:button, trigger, **trigger_button_attrs)
    end

    # `data:` is merged one level deeper than everything else, deliberately. A flat
    # merge would drop a caller's whole `data:` hash on the floor — silently, since
    # the component sets `data:` too and the last write wins — so a caller's own
    # hook would simply never appear with nothing to explain why.
    #
    # Keys are stringified before merging because `content_tag` de-duplicates
    # neither `:key` against `"key"` nor the reverse: it emits both and lets the
    # browser choose the winner.
    def trigger_button_attrs
      attrs = {}
      @trigger_attrs.each { |key, value| attrs[key.to_s] = value }
      caller_data = (attrs.delete("data") || {}).to_h { |key, value| [ key.to_s, value ] }

      attrs.merge(
        "type" => "button",
        "aria-haspopup" => "dialog",
        "aria-expanded" => "false",
        "aria-controls" => @id,
        "class" => cn(TRIGGER_BASE, @trigger_class),
        "data" => caller_data.merge("floating_target" => "trigger", "action" => "click->floating#toggle")
      )
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
