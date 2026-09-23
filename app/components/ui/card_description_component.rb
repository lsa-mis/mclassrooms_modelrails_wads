# frozen_string_literal: true

module UI
  # The muted subtitle paragraph under a card's title.
  # Usage, options and the accessibility contract: docs/components/card.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class CardDescriptionComponent < ApplicationComponent
    BASE = "text-text-muted text-sm"

    def initialize(text = nil, **html_attrs)
      @text = text || html_attrs.delete(:label) || html_attrs.delete(:text)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:p, content.presence || @text, class: cn(BASE, @extra_class), **@html_attrs)
    end
  end
end
