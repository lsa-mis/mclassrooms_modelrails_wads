# frozen_string_literal: true

module UI
  # A single row inside a `list_group`.
  # Usage, options and the accessibility contract: docs/components/list_group.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class ListGroupItemComponent < ApplicationComponent
    BASE = "flex items-center justify-between px-4 py-3 text-sm"

    # Interactive (link) rows get the shared focus-ring utility (AAA offset outline)
    # plus token-based hover/active — never focus:ring-* and never raw colors.
    LINK = "focus-ring transition-colors"

    VARIANTS = {
      default: "text-text-heading",
      active:  "bg-interactive text-text-on-interactive",
      muted:   "text-text-muted"
    }.freeze

    # Hover belongs to interactivity, not to colour variant, so it is applied only
    # in link_row — a static <li> highlighting full-width promises a click target
    # that does not exist (#191). Keyed by variant rather than folded into LINK
    # because LINK also dresses ACTIVE rows: an active row hovering to
    # bg-surface-sunken keeps text-text-on-interactive, which is white text on a
    # near-white surface in the light theme. The empty cell is the point.
    HOVER = {
      default: "hover:bg-surface-sunken",
      active:  "",
      muted:   "hover:bg-surface-sunken"
    }.freeze

    def initialize(label = nil, href: nil, active: false, variant: :default, **html_attrs)
      @label = label || html_attrs.delete(:label)
      @href = href
      @active = coerce_active(active, href)
      @variant = coerce_variant(@active ? :active : variant.to_sym)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      @href ? link_row : static_row
    end

    private

    # A navigable row: <a> inside its <li>. The link carries the row styling, the
    # focus-ring, and aria-current="page" when it is the active page.
    def link_row
      content_tag(:li) do
        content_tag(:a, body,
          href: @href,
          class: cn(BASE, LINK, VARIANTS.fetch(@variant), HOVER.fetch(@variant), @extra_class),
          "aria-current": (@active ? "page" : nil),
          **@html_attrs)
      end
    end

    # A static row: a plain, non-interactive <li>. Never focusable.
    def static_row
      content_tag(:li, body,
        class: cn(BASE, VARIANTS.fetch(@variant), @extra_class),
        **@html_attrs)
    end

    def body
      content.presence || @label
    end

    # `active` marks the CURRENT page among navigable rows, so it needs somewhere to
    # navigate. Without href: the row is a plain <li> wearing the solid interactive
    # fill on something that cannot be focused or activated — and static_row rightly
    # declines aria-current, so it reads as current to sighted users and is silent to
    # assistive technology. Same posture as coerce_variant: loud in dev/test, degrade
    # in production rather than 500 a page (#196).
    def coerce_active(active, href)
      return active if !active || href

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::ListGroupItemComponent: active: true needs an href:. " \
          "Add href:, or drop active: — a static row cannot be the current page."
      end

      false
    end

    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :default in production so a bad variant never
    # 500s a page. The Rails.respond_to?(:env) guard stays correct even when the
    # Rails module is defined but Rails.env isn't booted (the gem's Rails-less
    # render tests load rails/generators, which defines Rails without Rails.env).
    def coerce_variant(variant)
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::ListGroupItemComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")}."
      end

      :default
    end
  end
end
