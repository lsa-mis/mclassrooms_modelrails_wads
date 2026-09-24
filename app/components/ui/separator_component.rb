# frozen_string_literal: true

module UI
  # A thin rule that divides content along the horizontal or vertical axis.
  # Usage, options and the accessibility contract: docs/components/separator.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class SeparatorComponent < ApplicationComponent
    ORIENTATIONS = {
      horizontal: "bg-border h-px w-full shrink-0",
      vertical: "bg-border h-full w-px shrink-0"
    }.freeze

    def initialize(orientation: :horizontal, decorative: true, **html_attrs)
      @orientation = orientation.to_sym
      @decorative = decorative
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      attrs = {
        role: (@decorative ? "none" : "separator"),
        class: cn(ORIENTATIONS[@orientation], @extra_class)
      }
      # aria-orientation is invalid on role="none" — emit it only when the
      # separator is semantic (role="separator").
      attrs[:"aria-orientation"] = @orientation.to_s unless @decorative

      content_tag(:div, nil, **attrs, **@html_attrs)
    end
  end
end
