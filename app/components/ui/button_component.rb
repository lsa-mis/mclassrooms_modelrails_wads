# frozen_string_literal: true

module UI
  class ButtonComponent < ApplicationComponent
    # Applies the app's .btn-* classes (app/assets/tailwind/application.css @layer
    # components). This app-local copy intentionally diverges from modelrails_ui's
    # self-contained (raw-utility) ButtonComponent: this app owns its design tokens,
    # so the component points at the canonical CSS classes instead of re-listing them.
    #
    # Two-axis API (converged-conventions B2):
    #
    #   variant: :solid | :outline | :text   (shape, default :solid)
    #   tone:    :primary | :neutral | :danger  (signal, default :primary)
    #
    # Only AAA-proven (variant, tone) cells exist (COMBOS) — an unproven cell raises
    # in dev/test and falls back to [:solid, :primary] in prod (the combo-guard: a new
    # fill is an untested text-on-* pairing). The proven cells:
    #
    #   [:solid,   :primary]  filled brand     (.btn-primary)
    #   [:solid,   :danger]   filled danger    (.btn-danger)
    #   [:outline, :neutral]  bordered neutral (.btn-secondary)
    #   [:text,    :primary]  text/link brand  (.btn-text-interactive trio)
    #   [:text,    :danger]   text/link danger (.btn-text-danger trio)
    #
    # Legacy flat `variant:` values are still accepted via SHIM (back-compat,
    # byte-identical output): primary, secondary, danger, destructive, text,
    # text_interactive, text_danger. When a legacy value is passed, `tone:` is ignored.
    #
    # size: :default | :icon — :icon (A8) is a 44×44 square (WCAG 2.5.5): adds min-w
    # and drops horizontal padding (min-h is already carried by the .btn-* classes).

    # The proven (variant, tone) cells. Keys are [variant, tone]; values are the app's
    # canonical .btn-* classes (byte-identical to the former flat VARIANTS values).
    COMBOS = {
      [ :solid, :primary ] => "btn-primary",
      [ :solid, :danger ] => "btn-danger",
      [ :outline, :neutral ] => "btn-secondary",
      [ :text, :primary ] => "btn-touch-target btn-text btn-text-interactive",
      [ :text, :danger ] => "btn-touch-target btn-text btn-text-danger"
    }.freeze

    # Legacy flat `variant:` → [variant, tone]. Lets every existing call site keep
    # working unchanged (the new two-axis API is the canonical form).
    SHIM = {
      primary: [ :solid, :primary ],
      secondary: [ :outline, :neutral ],
      danger: [ :solid, :danger ],
      destructive: [ :solid, :danger ],
      text: [ :text, :primary ],
      text_interactive: [ :text, :primary ],
      text_danger: [ :text, :danger ]
    }.freeze

    # A8: :default keeps the standard horizontal padding; :icon is a 44×44 square.
    SIZES = { default: "", icon: "px-0 min-w-[var(--form-input-height)]" }.freeze

    # label — positional or keyword shorthand for plain-text buttons without a block.
    # href  — renders an <a> tag; sets tag: :a automatically.
    def initialize(label = nil, variant: :solid, tone: :primary, size: :default, href: nil, **html_attrs)
      @label = label || html_attrs.delete(:label)
      coerce_axes(variant, tone)
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

    # Resolve the (variant, tone) axes into @variant/@tone. An explicit proven cell
    # ([variant, tone] already in COMBOS) is used directly — this lets the new
    # `variant: :text, tone: :danger` form work even though `:text` also names a legacy
    # flat value. Otherwise, a legacy flat value in `variant:` is translated via SHIM
    # (ignoring the passed tone). Fail loud on an unproven cell in development/test so
    # misuse is caught immediately; fall back to [:solid, :primary] in production so a
    # bad combo never 500s a page. The Rails.respond_to?(:env) guard stays correct even
    # when the Rails module is defined but Rails.env isn't booted (the gem's Rails-less
    # tests load rails/generators, which defines Rails without Rails.env).
    def coerce_axes(variant, tone)
      variant = variant.to_sym
      @variant, @tone = variant, tone.to_sym
      return if COMBOS.key?([ @variant, @tone ])

      if SHIM.key?(variant)
        @variant, @tone = SHIM[variant]
        return
      end

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::ButtonComponent: unproven cell [#{@variant.inspect}, #{@tone.inspect}]. " \
          "Proven cells: #{COMBOS.keys.map(&:inspect).join(", ")}. " \
          "Legacy flat variant values are also accepted: #{SHIM.keys.join(", ")}."
      end

      @variant, @tone = :solid, :primary
    end

    def component_classes
      cn(COMBOS.fetch([ @variant, @tone ], COMBOS[[ :solid, :primary ]]), SIZES.fetch(@size, ""), @extra_class)
    end
  end
end
