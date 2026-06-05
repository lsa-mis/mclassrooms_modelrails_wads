# frozen_string_literal: true

module UI
  class ButtonComponent < ApplicationComponent
    # Reproduces the host app's .btn-* button system (app/assets/tailwind/application.css
    # @layer components). Filled family (primary/secondary/danger) + text family
    # (text/text_interactive/text_danger). All AAA-tuned, aligned to --form-input-height.
    FILLED = "inline-flex items-center justify-center px-4 rounded-md font-medium cursor-pointer " \
             "focus:outline-none focus:ring-2 focus:ring-offset-2 min-h-[var(--form-input-height)]"

    TEXT = "inline-flex items-center justify-center px-2 min-h-[var(--form-input-height)] min-w-[var(--form-input-height)] " \
           "font-medium underline rounded focus-visible:outline-none focus-visible:ring-2 hover:no-underline"

    VARIANTS = {
      primary: "#{FILLED} bg-interactive hover:bg-interactive-hover text-text-on-interactive focus:ring-interactive-focus",
      secondary: "#{FILLED} border border-border text-text-body hover:bg-surface-sunken focus:ring-interactive-focus",
      danger: "#{FILLED} bg-danger hover:bg-danger/90 text-text-on-interactive focus:ring-danger",
      text: "#{TEXT} text-interactive focus-visible:ring-interactive-focus",
      text_interactive: "#{TEXT} text-interactive focus-visible:ring-interactive-focus",
      text_danger: "#{TEXT} text-danger focus-visible:ring-danger"
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
