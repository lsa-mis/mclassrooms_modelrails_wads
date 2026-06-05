# frozen_string_literal: true

module UI
  class ButtonComponent < ApplicationComponent
    # Applies the host app's .btn-* button classes (see VARIANTS).
    # Applies the app's .btn-* classes (app/assets/tailwind/application.css @layer
    # components). This app-local copy intentionally diverges from modelrails_ui's
    # self-contained (raw-utility) ButtonComponent: this app owns its design tokens,
    # so the component points at the canonical CSS classes instead of re-listing them.
    VARIANTS = {
      primary: "btn-primary",
      secondary: "btn-secondary",
      danger: "btn-danger",
      text: "btn-touch-target btn-text btn-text-interactive",
      text_interactive: "btn-touch-target btn-text btn-text-interactive",
      text_danger: "btn-touch-target btn-text btn-text-danger"
    }.freeze

    # Optional size overrides (the app uses a single size keyed to --form-input-height,
    # so default is empty; kept for API symmetry / future use).
    SIZES = { default: "" }.freeze

    # `destructive` is a non-breaking alias for the canonical `danger`, so the whole
    # UI vocabulary speaks one severity ladder. Resolved in coerce_variant before lookup.
    VARIANT_ALIASES = { destructive: :danger }.freeze

    # label — positional or keyword shorthand for plain-text buttons without a block.
    # href  — renders an <a> tag; sets tag: :a automatically.
    def initialize(label = nil, variant: :primary, size: :default, href: nil, **html_attrs)
      @label = label || html_attrs.delete(:label)
      @variant = coerce_variant(variant.to_sym)
      @size = size.to_sym
      @tag = html_attrs.delete(:tag)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs

      if href
        @html_attrs[:href] = href
        @tag ||= :a
      end
    end

    def call
      body = content.presence || @label
      tag = @tag || :button
      attrs = @html_attrs.merge(class: component_classes)
      attrs[:type] ||= "button" if tag == :button && !attrs.key?(:type)
      content_tag(tag, body, **attrs)
    end

    private

    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :primary in production so a bad variant never
    # 500s a page. The Rails.respond_to?(:env) guard stays correct even when the Rails
    # module is defined but Rails.env isn't booted (the gem's Rails-less tests load
    # rails/generators, which defines Rails without Rails.env).
    def coerce_variant(variant)
      variant = VARIANT_ALIASES.fetch(variant, variant)
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::ButtonComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")} (alias: destructive→danger)."
      end

      :primary
    end

    def component_classes
      cn(VARIANTS.fetch(@variant, VARIANTS[:primary]), SIZES.fetch(@size, SIZES[:default]), @extra_class)
    end
  end
end
