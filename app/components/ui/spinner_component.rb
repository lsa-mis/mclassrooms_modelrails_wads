# frozen_string_literal: true

module UI
  # An animated busy indicator for indeterminate waits.
  # Usage, options and the accessibility contract: docs/components/spinner.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class SpinnerComponent < ApplicationComponent
    BASE = "inline-block animate-spin rounded-full border-2 border-current border-t-transparent"

    SIZES = {
      sm: "size-4",
      default: "size-6",
      lg: "size-10"
    }.freeze

    def initialize(size: :default, **html_attrs)
      @size = size.to_sym
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:span,
        content_tag(:span, I18n.t("modelrails_ui.spinner.loading", default: "Loading…"), class: "sr-only"),
        class: cn(BASE, SIZES.fetch(@size, SIZES[:default]), @extra_class),
        role: "status",
        **@html_attrs)
    end
  end
end
