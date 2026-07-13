# frozen_string_literal: true

module UI
  # # Banner
  #
  # A prominent page-level announcement strip — a promo, cookie notice, or system
  # message that spans the top of a page or section. Renders a labelled `region`
  # landmark and, when `dismissible:`, a real `<button>` to close it.
  #
  # ## Use when
  # - A standalone, page-level announcement: "We just shipped 2.0", a cookie
  #   consent strip, a scheduled-maintenance heads-up.
  #
  # ## Don't use when
  # - It's an inline message tied to surrounding content (a form-error summary, an
  #   empty-state notice) — use `alert`, which carries `role="alert"`/`status`.
  # - It's an ephemeral flash — use the app's toast system.
  #
  # ## Accessibility contract
  # - **Guarantees:** a `role="region"` landmark named by an i18n `aria-label` (so
  #   assistive tech can find and skip it), AAA-contrast text, and — when
  #   `dismissible:` — a real focusable `<button>` with an i18n accessible name
  #   ("Dismiss") and the `focus-ring` utility. A banner is NOT a live region: it
  #   is present on load, not announced, so it carries no `role="alert"`/`status`.
  # - **You supply:** the message (positional, `message:`/`label:`, or slot) and a
  #   valid `variant` (an unknown one raises in development).
  #
  # ## Dismiss behavior
  # When `dismissible:`, the banner root carries `data-controller="banner"` and the
  # trailing close button fires `banner#dismiss`, which removes the strip (immediate,
  # so it behaves under prefers-reduced-motion). The controller ships co-located
  # (`banner_controller.js`) and is auto-registered by the generator. Persistence
  # across page loads (a stable id + storage policy) is the host app's call — extend
  # the controller if you need it.
  #
  # ## Variants
  # `default` · `info` · `success` · `warning` · `destructive`
  # Signal variants use the tinted-surface treatment (`bg-<signal>-surface` +
  # `border-<signal>-border` + `text-<signal>`), never a solid signal fill.
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
        class: "-m-2 shrink-0 rounded-md inline-flex min-h-11 min-w-11 items-center justify-center text-current hover:opacity-80 focus-ring",
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
