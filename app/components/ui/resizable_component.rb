# frozen_string_literal: true

module UI
  # # Resizable
  #
  # Drag-to-resize panel layout — two (or more) panels separated by a draggable
  # **window splitter**. The handle is the APG window-splitter pattern: a
  # focusable `role="separator"` the user can grab with the mouse OR move with the
  # keyboard.
  #
  # Usage:
  #   ui :resizable, direction: :horizontal do |r|
  #     r.with_panel(min: 20, default: 30) { left_content }
  #     r.with_panel { right_content }
  #   end
  #
  # ## Accessibility contract
  # - **Guarantees (WCAG 2.1.1 keyboard):** every handle is a focusable
  #   `role="separator"` tab stop carrying the `focus-ring` indicator (the offset
  #   outline, never `focus:ring-*`), a named splitter (`aria-label`, i18n default),
  #   the `aria-orientation` it splits across, and the `aria-valuenow/valuemin/
  #   valuemax` range its controller keeps in sync. Arrow keys (← → for a
  #   horizontal split, ↑ ↓ for a vertical one) resize it; Home/End jump to the
  #   min/max. Pointer users still drag it.
  # - **You supply:** panels (each with optional `min`/`max`/`default` percentages).
  class ResizableComponent < ApplicationComponent
    # direction: which axis the panels lay out along. A :horizontal split puts
    # panels side-by-side, so the splitter bar itself is *vertical*.
    DIRECTIONS = {
      horizontal: { flex: "flex-row", orientation: "vertical" },
      vertical:   { flex: "flex-col", orientation: "horizontal" }
    }.freeze

    WRAPPER_CLS = "flex overflow-hidden rounded-lg border border-border"

    PANEL_CLS   = "overflow-auto"

    HANDLE_CLS  = "group relative flex items-center justify-center focus-ring bg-transparent " \
                  "before:absolute before:bg-border hover:before:bg-interactive-focus before:transition-colors " \
                  "data-[direction=horizontal]:w-11 data-[direction=horizontal]:cursor-col-resize " \
                  "data-[direction=horizontal]:before:inset-y-0 data-[direction=horizontal]:before:left-1/2 " \
                  "data-[direction=horizontal]:before:w-px data-[direction=horizontal]:before:-translate-x-1/2 " \
                  "data-[direction=vertical]:h-11 data-[direction=vertical]:cursor-row-resize " \
                  "data-[direction=vertical]:before:inset-x-0 data-[direction=vertical]:before:top-1/2 " \
                  "data-[direction=vertical]:before:h-px data-[direction=vertical]:before:-translate-y-1/2"

    HANDLE_GRIP = "z-10 h-4 w-1.5 rounded-sm border border-border bg-border"

    renders_many :panels, "UI::ResizableComponent::PanelComponent"

    # direction: :horizontal (default) | :vertical
    # aria_label: accessible name for each splitter (i18n default).
    def initialize(direction: :horizontal, aria_label: nil, **html_attrs)
      @direction   = direction.to_sym
      @aria_label  = aria_label
      @extra_class = html_attrs.delete(:class)
      # Merge (not overwrite) caller data so a passed `data:` can't clobber the
      # controller wiring that makes the splitter operable.
      @caller_data = html_attrs.delete(:data) || {}
      @html_attrs  = html_attrs
    end

    def call
      spec = DIRECTIONS.fetch(@direction) do
        raise ArgumentError,
          "Unknown resizable direction #{@direction.inspect} (expected one of #{DIRECTIONS.keys.inspect})"
      end

      content_tag(:div,
        class: cn(WRAPPER_CLS, spec[:flex], @extra_class),
        data: {
          controller: "resizable",
          resizable_direction_value: @direction
        }.merge(@caller_data),
        **@html_attrs) do
        panels.each_with_index do |panel, i|
          concat panel
          concat handle(spec, panels[i]) unless i == panels.size - 1
        end
      end
    end

    private

    # The splitter sits *after* a panel and resizes it, so its value range mirrors
    # that leading panel's min/max/default (valuenow defaults to the midpoint when
    # the panel has no explicit default).
    def handle(spec, leading_panel)
      now = leading_panel.default || 50

      content_tag(:div,
        class: HANDLE_CLS,
        "data-direction": @direction,
        tabindex: "0",
        role: "separator",
        "aria-label": @aria_label || I18n.t("ui.resizable.handle", default: "Resize panels"),
        "aria-orientation": spec[:orientation],
        "aria-valuenow": now,
        "aria-valuemin": leading_panel.min,
        "aria-valuemax": leading_panel.max,
        data: {
          resizable_target: "handle",
          action: "mousedown->resizable#startDrag touchstart->resizable#startDrag keydown->resizable#onKeydown"
        }) do
        # Decorative grip — the role/label already name the control.
        content_tag(:div, nil, class: HANDLE_GRIP, "aria-hidden": "true")
      end
    end

    class PanelComponent < ApplicationComponent
      attr_reader :min, :max, :default

      def initialize(min: 10, max: 90, default: nil, **html_attrs)
        @min     = min
        @max     = max
        @default = default
        @html_attrs = html_attrs
      end

      def call
        style = @default ? "flex: 0 0 #{@default}%" : "flex: 1"
        content_tag(:div, content,
          class: ResizableComponent::PANEL_CLS,
          style: style,
          data: {
            resizable_target: "panel",
            resizable_min_param: @min,
            resizable_max_param: @max
          },
          **@html_attrs)
      end
    end
  end
end
