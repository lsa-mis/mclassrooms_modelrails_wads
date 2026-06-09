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
  # - **Guarantees:** AAA-contrast text on every shipped cell's surface, including the
  #   adaptive signal treatments (`danger`/`success`/`info`/`warning`) which stay
  #   legible in dark mode.
  # - **You supply:** if the badge conveys status that isn't already in the
  #   surrounding text (e.g. a color-coded "danger" pill), give it an accessible
  #   name so screen-reader users get the same signal. A valid `(variant, tone)`
  #   cell is required — an unproven one raises in development.
  #
  # ## Axes (converged-conventions B2)
  # Two axes: `variant:` (shape) × `tone:` (signal).
  # - `variant: :solid | :soft | :outline | :ghost | :link` (default `:solid`)
  # - `tone: :primary | :neutral | :info | :success | :warning | :danger` (default `:primary`)
  #
  # Only the 9 AAA-proven cells ship (see `COMBOS`). Every signal lives on the SOFT
  # variant as a TINTED chip — note `[:soft, :danger]` is the badge "danger" (there is
  # NO solid-danger badge fill; `variant: :solid, tone: :danger` is unproven and raises).
  #
  # ## Legacy shim (deprecated flat `variant:` → `[variant, tone]`)
  # The historical flat values still work, byte-identically, via `SHIM`:
  # `default`→`[solid,primary]`, `secondary`→`[soft,primary]`, `info`→`[soft,info]`,
  # `success`→`[soft,success]`, `warning`→`[soft,warning]`, `danger`→`[soft,danger]`,
  # `destructive`→`[soft,danger]`, `outline`→`[outline,neutral]`, `ghost`→`[ghost,neutral]`,
  # `link`→`[link,primary]`. (`danger`/`destructive` map to the SOFT chip — NOT solid.)
  class BadgeComponent < ApplicationComponent
    BASE = "inline-flex w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-full " \
           "border border-transparent px-2 py-0.5 text-xs font-medium whitespace-nowrap " \
           "transition-[color,box-shadow] " \
           "focus-ring " \
           "aria-invalid:border-danger-border aria-invalid:ring-danger  " \
           "[&>svg]:pointer-events-none [&>svg]:size-3"

    # The 9 AAA-proven cells, keyed `[variant, tone]`. Signal tones use the TINTED
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
      end
    end

    def call
      content_tag(@tag || :span, content.presence || @label,
        class: cn(BASE, COMBOS.fetch([ @variant, @tone ], COMBOS[[ :solid, :primary ]]), @extra_class),
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
