# frozen_string_literal: true

module UI
  # A vertical, chronological sequence of events — each with a marker dot, an optional time, a title, and optional body.
  # Usage, options and the accessibility contract: docs/components/timeline.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class TimelineComponent < ApplicationComponent
    renders_many :items, "UI::TimelineComponent::ItemComponent"

    # The vertical connector is the `<ol>`'s left border — a pure CSS decoration
    # with no DOM node, so it is never announced. The ordered-list semantics carry
    # the sequence meaning to assistive tech.
    BASE = "relative border-l border-border ml-3"

    def initialize(**html_attrs)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:ol, **list_attrs) do
        safe_join(items)
      end
    end

    # Preflight strips the marker and Safari/VoiceOver drop the implicit list role
    # with it, so `role="list"` is load-bearing. Keys are stringified before the
    # caller's attrs merge: `content_tag` does not de-duplicate `:role` against
    # `"role"` — it emits both and lets the browser choose.
    def list_attrs
      attrs = { "role" => "list", "class" => cn(BASE, @extra_class) }
      @html_attrs.each { |key, value| attrs[key.to_s] = value }
      attrs
    end

    class ItemComponent < ApplicationComponent
      # Marker dots are SOLID fills (a dot must be a visible graphic, so the tinted
      # chip treatment used by alert/badge would be near-invisible at dot size).
      # Semantic tokens only — never raw palette. The dot is decorative
      # (`aria-hidden`); meaning is carried by the title/description text.
      VARIANTS = {
        default: "bg-interactive",
        info:    "bg-info",
        success: "bg-success",
        warning: "bg-warning",
        danger:  "bg-danger",
        muted:   "bg-text-muted"
      }.freeze

      # `destructive` is a non-breaking alias for the canonical `danger`.
      VARIANT_ALIASES = { destructive: :danger }.freeze

      DOT_CLS = "absolute -left-1.5 mt-1.5 size-3 rounded-full ring-4 ring-surface-raised shrink-0"
      # text-text-muted is AAA (resolves to the same neutral as text-text-body);
      # de-emphasis comes from size/weight, not a lower-contrast colour.
      DATE_CLS = "mb-0.5 block text-xs font-normal text-text-muted"
      TITLE_CLS = "text-sm font-medium text-text-heading leading-snug"
      DESC_CLS = "mt-1 text-sm text-text-muted"

      # title:       event label (required)
      # date:        optional human-readable date/time shown above the title
      # datetime:    optional machine-readable value for the <time datetime> attr
      # description: optional supporting text
      # variant:     dot colour — :default, :info, :success, :warning, :danger, :muted
      #              (:destructive is an alias for :danger)
      def initialize(title:, date: nil, datetime: nil, description: nil, variant: :default, **html_attrs)
        @title = title
        @date = date
        @datetime = datetime
        @description = description
        @variant = coerce_variant(variant.to_sym)
        @extra_class = html_attrs.delete(:class)
        @html_attrs = html_attrs
      end

      def call
        content_tag(:li, class: cn("mb-8 ml-4 last:mb-0", @extra_class), **@html_attrs) do
          concat dot
          concat time_tag if @date
          concat content_tag(:p, @title, class: TITLE_CLS)
          concat content_tag(:p, @description, class: DESC_CLS) if @description
          concat content if content?
        end
      end

      private

      def dot
        content_tag(:span, nil, class: cn(DOT_CLS, VARIANTS.fetch(@variant)), "aria-hidden": "true")
      end

      def time_tag
        attrs = { class: DATE_CLS }
        attrs[:datetime] = @datetime if @datetime
        content_tag(:time, @date, **attrs)
      end

      # Fail loud on an unknown variant in development/test so misuse is caught
      # immediately; fall back to :default in production so a bad variant never
      # 500s a page. The Rails.respond_to?(:env) guard stays correct even when the
      # Rails module is defined but Rails.env isn't booted (the gem's Rails-less
      # tests load rails/generators, which defines Rails without Rails.env).
      def coerce_variant(variant)
        variant = VARIANT_ALIASES.fetch(variant, variant)
        return variant if VARIANTS.key?(variant)

        unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
          raise ArgumentError,
            "UI::TimelineComponent::ItemComponent: unknown variant #{variant.inspect}. " \
            "Expected one of: #{VARIANTS.keys.join(", ")} (alias: destructive→danger)."
        end

        :default
      end
    end
  end
end
