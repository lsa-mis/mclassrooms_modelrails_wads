# frozen_string_literal: true

module UI
  # A small status dot or count badge anchored to the corner of another element (an icon, an avatar, a button).
  # Usage, options and the accessibility contract: docs/components/indicator.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class IndicatorComponent < ApplicationComponent
    DOT_BASE = "absolute flex items-center justify-center rounded-full text-[10px] font-medium leading-none"

    # `text-text-on-interactive` (not `text-white`) on filled dots: the adaptive token
    # stays AAA-legible in both themes. info/success/warning graphic contrast: CI-verify.
    # Dots use a SOLID fill (like the brand `default`): a dot must be a visible graphic,
    # so the tinted chip treatment used by alert/badge would be near-invisible at dot
    # size. `text-text-on-interactive` (adaptive — white in light, dark in dark) keeps
    # the count text AAA on the dark-enough base fills. `warning` uses it too — NOT the
    # non-adaptive `text-text-heading`, which went low-contrast in BOTH themes (it tracked
    # the fill's lightness instead of opposing it). Dot graphic contrast: CI-verify.
    VARIANTS = {
      default: "bg-interactive text-text-on-interactive",
      info:    "bg-info text-text-on-interactive",
      success: "bg-success text-text-on-interactive",
      warning: "bg-warning text-text-on-interactive",
      danger:  "bg-danger text-text-on-interactive"
    }.freeze

    # `destructive` is a non-breaking alias for the canonical `danger`. Resolved in
    # coerce_variant before lookup.
    VARIANT_ALIASES = { destructive: :danger }.freeze

    POSITIONS = {
      top_right:    "-top-1 -right-1",
      top_left:     "-top-1 -left-1",
      bottom_right: "-bottom-1 -right-1",
      bottom_left:  "-bottom-1 -left-1"
    }.freeze

    def initialize(count: nil, position: :top_right, variant: :default, **html_attrs)
      @count = count
      @position = position.to_sym
      @variant = coerce_variant(variant.to_sym)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:span, class: cn("relative inline-flex", @extra_class), **@html_attrs) do
        concat content
        concat dot
      end
    end

    private

    def dot
      dot_size = @count ? "size-5 min-w-5 px-0.5" : "size-2"
      content_tag(:span, @count,
        class: cn(DOT_BASE, dot_size,
          VARIANTS.fetch(@variant),
          POSITIONS.fetch(@position, POSITIONS[:top_right])))
    end

    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :default in production so a bad variant never
    # 500s a page. The Rails.respond_to?(:env) guard stays correct even when the Rails
    # module is defined but Rails.env isn't booted (the gem's Rails-less tests load
    # rails/generators, which defines Rails without Rails.env).
    def coerce_variant(variant)
      variant = VARIANT_ALIASES.fetch(variant, variant)
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::IndicatorComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")} (alias: destructive→danger)."
      end

      :default
    end
  end
end
