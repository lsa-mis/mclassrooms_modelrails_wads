# frozen_string_literal: true

module UI
  # The placeholder shown where a list, table or panel would be if it had anything in it — an optional icon, a title, an optional supporting line, and an optional call to action.
  # Usage, options and the accessibility contract: docs/components/empty_state.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class EmptyStateComponent < ApplicationComponent
    # The icon's gap lives on the SVG, not on the title: preflight makes the svg a
    # block, and the margin has to belong to the optional element — on the title it
    # would indent an icon-less empty state and leave an icon + description pair
    # flush. (#241)
    BASE = "px-6 py-10 text-center " \
           "[&>svg]:mx-auto [&>svg]:size-8 [&>svg]:text-text-muted [&>svg]:mb-3"

    # Three surfaces, each from a real call site rather than invented:
    #   dashed   — the default "nothing here yet" well
    #   outlined — a filled card, for an empty state sitting among other cards
    #   plain    — no chrome at all, for a no-results block inside an existing panel
    #
    # `outlined` is bg-surface-raised, never bg-surface: bg-surface is the PAGE, so a
    # container painted with it is the colour of the ground beneath it. See
    # docs/design-tokens.md.
    VARIANTS = {
      dashed: "rounded-lg border border-dashed border-border",
      outlined: "rounded-lg border border-border bg-surface-raised",
      plain: ""
    }.freeze

    renders_one :icon
    renders_one :action

    def initialize(title: nil, description: nil, variant: :dashed, **html_attrs)
      @title = title || html_attrs.delete(:label)
      @description = description
      @variant = coerce_variant(variant.to_sym)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, class: cn(BASE, VARIANTS.fetch(@variant), @extra_class), **@html_attrs) do
        safe_join([ icon, title_text, description_text, action_area ].compact)
      end
    end

    private

    # A <p>, deliberately not a heading. An empty state is transient content that can
    # appear anywhere on a page, so emitting an <h2>/<h3> would inject a heading at an
    # arbitrary level and break the document's outline for anyone navigating by
    # headings. A caller who genuinely needs one passes it as block content instead.
    def title_text
      return if @title.blank?

      content_tag(:p, @title, class: "text-text-heading font-medium", data: { slot: "empty-state-title" })
    end

    def description_text
      return if @description.blank?

      content_tag(:p, @description,
        class: "mt-1 text-sm text-text-body", data: { slot: "empty-state-description" })
    end

    def action_area
      return unless action?

      content_tag(:div, action, class: "mt-4", data: { slot: "empty-state-action" })
    end

    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :dashed in production so a bad variant never 500s a
    # page. The Rails.respond_to?(:env) guard stays correct even when the Rails module
    # is defined but Rails.env isn't booted (the gem's Rails-less render tests).
    def coerce_variant(variant)
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::EmptyStateComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")}."
      end

      :dashed
    end
  end
end
