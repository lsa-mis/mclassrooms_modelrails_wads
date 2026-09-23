# frozen_string_literal: true

module UI
  # The padded body of a card.
  # Usage, options and the accessibility contract: docs/components/card.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class CardContentComponent < ApplicationComponent
    BASE = "px-6"

    def initialize(**html_attrs)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, content, class: cn(BASE, @extra_class), **@html_attrs)
    end
  end
end
