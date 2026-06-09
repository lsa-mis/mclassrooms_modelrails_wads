# frozen_string_literal: true

module UI
  # # DeviceMockup
  #
  # A decorative device frame — phone, tablet, or browser window — that wraps any
  # content (a screenshot, an `<img>`, an iframe). The CHROME (bezel, notch,
  # traffic-light dots, address bar) is purely presentational; the slotted CONTENT
  # carries its own accessibility.
  #
  # ## Use when
  # - You're showing a product screenshot or demo inside a recognizable device
  #   shell for marketing/docs context.
  #
  # ## Don't use when
  # - The frame would imply interactivity the content doesn't have — the mockup is
  #   a static decorative wrapper, not a live device.
  #
  # ## Accessibility contract
  # - **Guarantees:** the frame is a plain `<div>` (no bogus role), and every purely
  #   decorative chrome bit (notch, traffic-light dots, fake address bar) is
  #   `aria-hidden` so assistive tech sees ONLY the slotted content. AAA semantic
  #   tokens throughout (`bg-surface-sunken`/`border-border`/`text-text-*`) — no raw
  #   palette colors. A valid `variant` is required (an unknown one raises in dev).
  # - **You supply:** the framed content via the block, with its own a11y — real
  #   `alt` text on a meaningful screenshot, or `alt: ""` for a decorative one.
  class DeviceMockupComponent < ApplicationComponent
    VARIANTS = {
      phone: {
        outer:  "relative mx-auto h-[600px] w-[300px] rounded-[2.5rem] border-[14px] " \
                "border-text-heading bg-text-heading shadow-xl",
        screen: "relative h-full w-full overflow-hidden rounded-[2rem] bg-surface",
        notch:  "absolute left-1/2 top-0 z-10 h-6 w-28 -translate-x-1/2 rounded-b-2xl bg-text-heading"
      },
      browser: {
        outer:  "relative mx-auto overflow-hidden rounded-xl border border-border bg-surface-raised shadow-xl",
        bar:    "flex h-10 items-center gap-2 border-b border-border bg-surface-sunken px-4",
        dots:   "flex gap-1.5",
        screen: "overflow-hidden bg-surface"
      },
      tablet: {
        outer:  "relative mx-auto h-[500px] w-[700px] rounded-[1.75rem] border-[12px] " \
                "border-text-heading bg-text-heading shadow-xl",
        screen: "relative h-full w-full overflow-hidden rounded-[1.25rem] bg-surface",
        notch:  nil
      }
    }.freeze

    # The macOS traffic-light dots are decorative chrome. They use semantic signal
    # fills (success/warning/danger) rather than raw palette colors so they track
    # the theme; the whole dot cluster is aria-hidden, so this is cosmetic, not a
    # color-coded signal the user must perceive.
    DOT_COLORS = %w[bg-danger bg-warning bg-success].freeze

    # variant: :phone (default) | :browser | :tablet
    # url:     address bar text for :browser variant (caller-supplied)
    def initialize(variant: :phone, url: nil, **html_attrs)
      @variant = coerce_variant(variant.to_sym)
      @url     = url
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      cfg = VARIANTS.fetch(@variant)

      content_tag(:div, class: cn(cfg[:outer], @extra_class), **@html_attrs) do
        if @variant == :browser
          concat browser_bar(cfg)
          concat content_tag(:div, content, class: cfg[:screen])
        else
          concat content_tag(:div, nil, class: cfg[:notch], "aria-hidden": "true") if cfg[:notch]
          concat content_tag(:div, content, class: cfg[:screen])
        end
      end
    end

    private

    # The browser chrome (dots + fake address bar) is decorative — aria-hidden so
    # AT announces only the slotted content, never the cosmetic URL string.
    def browser_bar(cfg)
      content_tag(:div, class: cfg[:bar], "aria-hidden": "true") do
        concat(content_tag(:div, class: cfg[:dots]) {
          DOT_COLORS.each do |color|
            concat content_tag(:div, nil, class: "size-3 rounded-full #{color}")
          end
        })
        if @url
          concat content_tag(:div, @url,
            class: "ml-4 flex-1 truncate rounded-md bg-surface-raised px-3 py-1 text-xs text-text-muted")
        end
      end
    end

    # Fail loud on an unknown variant in development/test so misuse is caught
    # immediately; fall back to :phone in production so a bad variant never 500s a
    # page. The Rails.respond_to?(:env) guard stays correct even when the Rails
    # module is defined but Rails.env isn't booted (the gem's Rails-less tests load
    # rails/generators, which defines Rails without Rails.env).
    def coerce_variant(variant)
      return variant if VARIANTS.key?(variant)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::DeviceMockupComponent: unknown variant #{variant.inspect}. " \
          "Expected one of: #{VARIANTS.keys.join(", ")}."
      end

      :phone
    end
  end
end
