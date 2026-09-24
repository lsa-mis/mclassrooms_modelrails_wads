# frozen_string_literal: true

module UI
  # A presentational content container, optionally composed of header / content / footer regions via the sibling sub-components.
  # Usage, options and the accessibility contract: docs/components/card.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class CardComponent < ApplicationComponent
    BASE = "bg-surface-raised text-text-body flex flex-col gap-6 rounded-xl border border-border py-6 shadow-sm"

    def initialize(**html_attrs)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, content, class: cn(BASE, @extra_class), **@html_attrs)
    end
  end
end
