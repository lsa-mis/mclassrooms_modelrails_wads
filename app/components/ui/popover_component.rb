# frozen_string_literal: true

module UI
  # # Popover
  #
  # A non-modal floating panel anchored to a trigger button. Behavior lives in the
  # `floating` Stimulus controller shipped alongside this component; positioning is
  # CSS (a `relative` wrapper + `absolute` panel — the author picks `side`/`align`).
  #
  # ## Use when
  # - You need a small interactive overlay (a menu of actions, a filter form, details)
  #   tied to a trigger that does NOT need to block the page.
  #
  # ## Don't use when
  # - The content must block interaction until dismissed — use `dialog`/`alert_dialog`.
  # - You only need a hint describing a control — use `tooltip`.
  # - The trigger sits inside an `overflow:hidden` / transformed ancestor that would
  #   clip the panel (there is no top layer) — restructure or use a `dialog`.
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

    PANEL_BASE = "absolute z-50 w-72 rounded-md border border-border bg-surface-overlay p-4 " \
                 "text-sm text-text-body shadow-md outline-none"

    ALIGN = {
      start:  "left-0",
      center: "left-1/2 -translate-x-1/2",
      end:    "right-0"
    }.freeze

    SIDE = {
      bottom: "top-full mt-2",
      top:    "bottom-full mb-2",
      left:   "right-full mr-2 top-0",
      right:  "left-full ml-2 top-0"
    }.freeze

    # label:         the panel's accessible name (required → aria-label on role=dialog)
    # id:            panel id (auto-generated if omitted; wired to aria-controls)
    # align:         :start | :center | :end
    # side:          :bottom | :top | :left | :right
    # trigger_class: CSS for the trigger button (default canonical .btn-secondary)
    def initialize(label:, id: nil, align: :start, side: :bottom, trigger_class: "btn-secondary", **html_attrs)
      @label         = label
      @id            = id || "popover-#{SecureRandom.hex(4)}"
      @align         = coerce_enum(:align, align, ALIGN)
      @side          = coerce_enum(:side, side, SIDE)
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
        data: { floating_target: "panel" },
        class: cn(PANEL_BASE, ALIGN.fetch(@align), SIDE.fetch(@side)))
    end

    def coerce_enum(name, value, map)
      key = value.to_sym
      return key if map.key?(key)

      raise ArgumentError,
        "UI::Popover unknown #{name}: #{value.inspect} (allowed: #{map.keys.join(", ")})"
    end
  end
end
