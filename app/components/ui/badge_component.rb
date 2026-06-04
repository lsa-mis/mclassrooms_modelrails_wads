# frozen_string_literal: true

module UI
  # # Badge
  #
  # A small status/category label — a compact, non-interactive pill that tags a
  # surrounding item (a status, a count, a category). Renders a `<span>` by default,
  # or an `<a>` when `href:` is given (a clickable tag/filter link).
  #
  # ## Use when
  # - You need a short inline label that classifies or annotates nearby content:
  #   a status pill ("Active"), a category tag, a small count.
  #
  # ## Don't use when
  # - It's a real action — use `UI::ButtonComponent` (or `button_to` for non-GET).
  #   A badge is presentational; `href:` is for navigation/filtering, not actions.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA-contrast text on every variant's surface, including the
  #   adaptive `destructive` treatment (which stays legible in dark mode).
  # - **You supply:** if the badge conveys status that isn't already in the
  #   surrounding text (e.g. a color-coded "destructive" pill), give it an accessible
  #   name so screen-reader users get the same signal. A valid `variant` is required —
  #   an unknown one raises in development.
  #
  # ## Variants
  # `default` · `secondary` · `destructive` · `outline` · `ghost` · `link`
  class BadgeComponent < ApplicationComponent
    BASE = "inline-flex w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-full " \
           "border border-transparent px-2 py-0.5 text-xs font-medium whitespace-nowrap " \
           "transition-[color,box-shadow] " \
           "focus-visible:border-border-focus focus-visible:ring-[3px] focus-visible:ring-interactive-focus " \
           "aria-invalid:border-danger-border aria-invalid:ring-danger  " \
           "[&>svg]:pointer-events-none [&>svg]:size-3"

    # `text-text-on-interactive` (not `text-white`) on destructive: the adaptive token
    # is white in light mode and a dark neutral in dark mode, so it keeps AAA contrast
    # against the light-pink dark-mode `--color-danger` — exactly how the danger button
    # handles it. Raw `text-white` would fail AAA on that dark surface.
    VARIANTS = {
      default: "bg-interactive text-text-on-interactive [a&]:hover:bg-interactive-hover",
      secondary: "bg-interactive-subtle text-interactive [a&]:hover:bg-interactive-subtle",
      destructive: "bg-danger text-text-on-interactive focus-visible:ring-danger " \
                   "  [a&]:hover:bg-danger-hover",
      outline: "border-border text-text-heading [a&]:hover:bg-surface-sunken [a&]:hover:text-text-heading",
      ghost: "[a&]:hover:bg-surface-sunken [a&]:hover:text-text-heading",
      link: "text-interactive underline-offset-4 [a&]:hover:underline"
    }.freeze

    # label — positional or keyword shorthand for plain-text badges without a block.
    # href  — renders an <a> tag (a clickable tag/filter link); sets tag: :a automatically.
    def initialize(label = nil, variant: :default, href: nil, **html_attrs)
      @label = label || html_attrs.delete(:label)
      @variant = coerce_variant(variant.to_sym)
      @tag = html_attrs.delete(:tag)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs

      if href
        @html_attrs[:href] = href
        @tag ||= :a
      end
    end

    def call
      content_tag(@tag || :span, content.presence || @label,
        class: cn(BASE, VARIANTS.fetch(@variant), @extra_class),
        **@html_attrs)
    end

    private

    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :default in production so a bad variant never
    # 500s a page. The Rails.respond_to?(:env) guard stays correct even when the Rails
    # module is defined but Rails.env isn't booted (the gem's Rails-less tests load
    # rails/generators, which defines Rails without Rails.env).
    def coerce_variant(variant)
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::BadgeComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")}."
      end

      :default
    end
  end
end
