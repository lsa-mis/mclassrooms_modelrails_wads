# frozen_string_literal: true

module UI
  # A pulsing placeholder block that stands in for content while it loads.
  # Usage, options and the accessibility contract: docs/components/skeleton.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class SkeletonComponent < ApplicationComponent
    BASE = "bg-surface-sunken animate-pulse motion-reduce:animate-none rounded-md"

    def initialize(**html_attrs)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, nil,
        class: cn(BASE, @extra_class),
        "aria-hidden": "true",
        **@html_attrs)
    end
  end
end
