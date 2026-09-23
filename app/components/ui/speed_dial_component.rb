# frozen_string_literal: true

module UI
  class SpeedDialComponent < ApplicationComponent
    # Floating action button (FAB) that expands into a stack of sub-action buttons.
    # Usage, options and the accessibility contract: docs/components/speed_dial.md in the
    # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.

    FAB_CLS = "relative z-50 inline-flex size-14 items-center justify-center rounded-full " \
              "bg-interactive text-text-on-interactive shadow-lg transition-transform " \
              "hover:bg-interactive-hover focus-ring active:scale-95"

    PANEL_CLS = "absolute bottom-16 right-0 flex flex-col-reverse items-end gap-2"

    ACTION_CLS = "flex items-center gap-2 rounded-full bg-surface-raised px-4 py-2 text-sm font-medium " \
                 "shadow-md border border-border transition-colors " \
                 "hover:bg-surface-sunken hover:text-text-heading focus-ring " \
                 "whitespace-nowrap"

    PLUS_PATH = "M12 5v14M5 12h14"

    # position: which corner the dial anchors to (and which way actions stack).
    POSITIONS = {
      bottom_right:  "fixed bottom-6 right-6",
      bottom_left:   "fixed bottom-6 left-6",
      bottom_center: "fixed bottom-6 left-1/2 -translate-x-1/2"
    }.freeze

    renders_many :actions, "UI::SpeedDialComponent::ActionComponent"

    # position: :bottom_right (default) | :bottom_left | :bottom_center
    # label:    accessible name for the FAB (default: i18n "Open actions")
    def initialize(position: :bottom_right, label: nil, **html_attrs)
      @position    = coerce_position(position)
      @label       = label
      @panel_id    = "speed-dial-panel-#{SecureRandom.hex(4)}"
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      # Merge the controller wiring UNDER any caller-supplied data: so passthrough
      # attrs never clobber the speed-dial controller/action binding.
      caller_data = @html_attrs.delete(:data) || {}
      content_tag(:div,
        class: cn("relative", POSITIONS.fetch(@position), @extra_class),
        data: {
          controller: "speed-dial",
          action: "click@document->speed-dial#closeOnClickOutside"
        }.merge(caller_data),
        **@html_attrs) do
        concat action_panel
        concat fab_button
      end
    end

    private

    def coerce_position(value)
      key = value.to_sym
      return key if POSITIONS.key?(key)

      raise ArgumentError,
        "UI::SpeedDialComponent: unknown position #{value.inspect}. " \
        "Expected one of: #{POSITIONS.keys.join(", ")}."
    end

    def fab_button
      content_tag(:button,
        type: "button",
        class: FAB_CLS,
        "aria-expanded": "false",
        "aria-controls": @panel_id,
        "aria-label": @label || I18n.t("modelrails_ui.speed_dial.open", default: "Open actions"),
        data: {
          speed_dial_target: "fab",
          action: "click->speed-dial#toggle"
        }) do
        plus_icon
      end
    end

    def action_panel
      content_tag(:div,
        id: @panel_id,
        class: PANEL_CLS,
        hidden: true,
        data: { speed_dial_target: "panel" }) do
        safe_join(actions)
      end
    end

    def plus_icon
      content_tag(:svg,
        content_tag(:path, nil, d: PLUS_PATH, "stroke-linecap": "round", "stroke-linejoin": "round"),
        xmlns: "http://www.w3.org/2000/svg",
        viewBox: "0 0 24 24",
        fill: "none",
        stroke: "currentColor",
        "stroke-width": "2",
        class: "size-6 transition-transform duration-200",
        "aria-hidden": "true",
        data: { speed_dial_target: "icon" })
    end

    class ActionComponent < ApplicationComponent
      def initialize(label:, href: nil, icon: nil, **html_attrs)
        @label      = label
        @href       = href
        @icon       = icon
        @html_attrs = html_attrs
      end

      def call
        tag_name = @href ? :a : :button
        attrs    = { class: SpeedDialComponent::ACTION_CLS, **@html_attrs }
        attrs[:href] = @href if @href
        attrs[:type] = "button" if tag_name == :button
        content_tag(tag_name, @label, **attrs)
      end
    end
  end
end
