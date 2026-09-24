# frozen_string_literal: true

module UI
  # A small status/category label — a compact, non-interactive pill that tags a surrounding item (a status, a count, a category).
  # Usage, options and the accessibility contract: docs/components/badge.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class BadgeComponent < ApplicationComponent
    BASE = "inline-flex w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-full " \
           "border border-transparent px-2 py-0.5 text-xs font-medium whitespace-nowrap " \
           "transition-colors " \
           "aria-invalid:border-2 aria-invalid:border-danger " \
           "[&>svg]:pointer-events-none [&>svg]:size-3"

    # The 10 shipped cells, keyed `[variant, tone]` — 9 AAA-proven, plus `[:soft, :neutral]`
    # pending this app's 0b axe row (see the class docblock). Signal tones use the TINTED
    # treatment (soft `*-surface` background + saturated `text-<level>` + `*-border`),
    # matching the alert + toast cards. The `--color-<level>` base tokens are TEXT
    # colors (dark in light mode for AAA-on-light readability), so using them as solid
    # fills produces dark, muddy chips — e.g. `bg-warning` is amber-900 (a dark brown),
    # which reads nothing like "warning." The tinted pairing is what the `*-surface`
    # tokens are for, and `text-<level>` on `bg-<level>-surface` is AAA-proven on the
    # toast cards. (info/success on their tinted surfaces: CI-verify.)
    COMBOS = {
      [ :solid, :primary ] => "bg-interactive text-text-on-interactive [a&]:hover:bg-interactive-hover",
      [ :soft, :primary ] => "bg-interactive-subtle text-interactive [a&]:hover:bg-interactive-subtle",
      [ :soft, :info ] => "bg-info-surface text-info border-info-border [a&]:hover:bg-info-hover",
      [ :soft, :success ] => "bg-success-surface text-success border-success-border [a&]:hover:bg-success-hover",
      [ :soft, :warning ] => "bg-warning-surface text-warning border-warning-border [a&]:hover:bg-warning-hover",
      [ :soft, :danger ] => "bg-danger-surface text-danger border-danger-border [a&]:hover:bg-danger-hover",
      [ :soft, :neutral ] => "bg-surface text-text-muted border-border [a&]:hover:bg-surface-sunken [a&]:hover:text-text-heading",
      [ :outline, :neutral ] => "border-border text-text-heading [a&]:hover:bg-surface-sunken [a&]:hover:text-text-heading",
      [ :ghost, :neutral ] => "[a&]:hover:bg-surface-sunken [a&]:hover:text-text-heading",
      [ :link, :primary ] => "text-interactive underline-offset-4 [a&]:hover:underline"
    }.freeze

    # Legacy flat `variant:` values → `[variant, tone]`. Per-component (badge `danger`
    # is the SOFT chip, so `danger`/`destructive`→`[soft,danger]` — NOT solid, unlike
    # button). When a caller passes one of these in `variant:`, the shim wins and the
    # passed `tone:` is ignored.
    SHIM = {
      default: [ :solid, :primary ], secondary: [ :soft, :primary ], info: [ :soft, :info ],
      success: [ :soft, :success ], warning: [ :soft, :warning ], danger: [ :soft, :danger ],
      destructive: [ :soft, :danger ], outline: [ :outline, :neutral ], ghost: [ :ghost, :neutral ],
      link: [ :link, :primary ]
    }.freeze

    # label   — positional or keyword shorthand for plain-text badges without a block.
    # variant — shape axis (see COMBOS); also accepts a legacy flat value via SHIM.
    # tone    — signal axis (see COMBOS); ignored when `variant:` is a legacy flat value.
    # href    — renders an <a> tag (a clickable tag/filter link); sets tag: :a automatically.
    def initialize(label = nil, variant: :solid, tone: :primary, href: nil, **html_attrs)
      @label = label || html_attrs.delete(:label)
      coerce_axes(variant, tone)
      @tag = html_attrs.delete(:tag)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs

      if href
        @html_attrs[:href] = href
        @tag ||= :a
        @extra_class = [ @extra_class, "min-h-input focus-ring" ].compact.join(" ")
      end
    end

    def call
      content_tag(@tag || :span, content.presence || @label,
        class: cn(BASE, COMBOS.fetch([ @variant, @tone ], COMBOS[[ :solid, :primary ]]), @extra_class),
        "data-variant": @variant, "data-tone": @tone,
        **@html_attrs)
    end

    private

    # Resolve the (variant, tone) cell. A legacy flat value in `variant:` is translated
    # through SHIM (passed `tone:` ignored); otherwise the two axes are used directly.
    # Fail loud on an unproven cell in development/test so misuse is caught immediately;
    # fall back to [:solid, :primary] in production so a bad cell never 500s a page. The
    # Rails.respond_to?(:env) guard stays correct even when the Rails module is defined
    # but Rails.env isn't booted (the gem's Rails-less tests load rails/generators, which
    # defines Rails without Rails.env).
    def coerce_axes(variant, tone)
      variant = variant.to_sym
      if SHIM.key?(variant)
        @variant, @tone = SHIM[variant]
      else
        @variant, @tone = variant, tone.to_sym
      end
      return if COMBOS.key?([ @variant, @tone ])

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::BadgeComponent: unproven cell [#{@variant.inspect}, #{@tone.inspect}]. " \
          "Expected one of: #{COMBOS.keys.map(&:inspect).join(", ")} " \
          "(legacy flat aliases: #{SHIM.keys.join(", ")})."
      end

      @variant, @tone = :solid, :primary
    end
  end
end
