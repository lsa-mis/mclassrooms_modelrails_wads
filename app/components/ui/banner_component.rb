# frozen_string_literal: true

module UI
  # A prominent page-level announcement strip — a promo, cookie notice, or system message that spans the top of a page or section.
  # Usage, options and the accessibility contract: docs/components/banner.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class BannerComponent < ApplicationComponent
    BASE = "flex items-center gap-3 rounded-lg border p-4 text-sm"

    # Signal variants share the tinted-surface treatment used by `alert` and the
    # toast cards (`bg-<signal>-surface` + `border-<signal>-border` + `text-<signal>`).
    # Base signal tokens are TEXT colors, so the fill is the dedicated `-surface`
    # token — never `bg-<signal>` (a solid fill) or an opacity hack like `bg-<signal>/10`.
    VARIANTS = {
      default:     "bg-surface-raised border-border text-text-body",
      info:        "bg-info-surface border-info-border text-info",
      success:     "bg-success-surface border-success-border text-success",
      warning:     "bg-warning-surface border-warning-border text-warning",
      destructive: "bg-danger-surface border-danger-border text-danger"
    }.freeze

    # The dismiss control tints on hover rather than fading. An opacity fade
    # reads as DISABLED — the rule already beside .btn-text-icon — and on a
    # tinted chip it drags the icon toward the surface behind it, the one
    # direction that loses contrast on the control most likely to be clicked in
    # a hurry. Keyed by variant because the ground differs per tone; the icon is
    # non-text, so the floor here is 3:1, not 7:1 (modelrails_ui #256).
    DISMISS_HOVER = {
      default:     "hover:bg-surface-sunken",
      info:        "hover:bg-info-hover",
      success:     "hover:bg-success-hover",
      warning:     "hover:bg-warning-hover",
      destructive: "hover:bg-danger-hover"
    }.freeze

    # message:     banner text — positional, `message:`, or `label:` keyword, or block content
    # variant:     visual style (unknown raises in development)
    # dismissible: render a trailing close <button> (needs the `banner` controller to act)
    # label:       region accessible name (i18n; defaults to t("ui.banner.label", default: "Announcement"))
    def initialize(message = nil, variant: :default, dismissible: false, label: nil, **html_attrs)
      @message = message || html_attrs.delete(:message)
      @variant = resolve_variant(variant)
      @dismissible = dismissible
      @region_label = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, banner_body,
        **@html_attrs,
        role: "region",
        "aria-label": region_label,
        class: cn(BASE, VARIANTS.fetch(@variant), @extra_class),
        data: dismiss_root_data)
    end

    private

    # t() is resolved at RENDER time (here, not in initialize — no view context there).
    def region_label
      @region_label || t("ui.banner.label", default: "Announcement")
    end

    def banner_body
      safe_join([ message_content, dismiss_button ].compact)
    end

    def message_content
      content_tag(:div, content.presence || @message, class: "flex-1")
    end

    # The dismiss control is a real <button> (focusable, keyboard-operable) with an
    # i18n accessible name and the `focus-ring` utility (NEVER focus:ring-* — clipped /
    # forced-colors-mode fails). It hooks the `banner` controller's dismiss action.
    def dismiss_button
      return unless @dismissible

      content_tag(:button, dismiss_icon,
        type: "button",
        "aria-label": dismiss_label,
        class: cn("-m-2 shrink-0 rounded-md inline-flex min-h-input min-w-11 items-center justify-center text-current focus-ring transition-colors",
                  DISMISS_HOVER.fetch(@variant, DISMISS_HOVER[:default])),
        data: { action: "banner#dismiss" })
    end

    def dismiss_root_data
      @dismissible ? { controller: "banner" } : {}
    end

    def dismiss_label
      t("ui.banner.dismiss", default: "Dismiss")
    end

    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :default in production so a bad variant never 500s
    # a page. The Rails.respond_to?(:env) guard stays correct even when the Rails
    # module is defined but Rails.env isn't booted (the gem's Rails-less render
    # tests load rails/generators, which defines Rails without Rails.env).
    def resolve_variant(variant)
      variant = variant.to_sym
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::BannerComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")}."
      end

      :default
    end

    def dismiss_icon
      if helpers.respond_to?(:icon)
        helpers.icon(:x_mark, size: :sm)
      else
        raw('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" ' \
            'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' \
            '<path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>')
      end
    end
  end
end
