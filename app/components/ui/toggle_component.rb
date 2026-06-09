# frozen_string_literal: true

module UI
  # # Toggle
  #
  # A two-state press button — an `<button type="button">` carrying `aria-pressed`
  # (and a mirrored `data-state`) that flips on click. Use it for a standalone
  # on/off control (bold, mute, pin), not as a checkbox replacement in a form.
  #
  # ## Use when
  # - You need a single, instantly-applied on/off action with no separate submit.
  #
  # ## Don't use when
  # - It's a form field whose value posts on submit — use a checkbox/switch input.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real interactive element with `aria-pressed` reflecting the
  #   pressed state, and a 44px-minimum touch target at every size (AAA 2.5.5).
  # - **You supply:** an accessible name — visible text/content, or an `aria-label:`
  #   for an icon-only toggle — and a valid `size` (an unknown one raises in development).
  #
  # ## Sizes
  # `default` · `sm` · `lg` — all rendered >=44px tall (the AAA target-size floor).
  class ToggleComponent < ApplicationComponent
    # Hover and selected are intentionally DISTINCT surfaces so clicking to select
    # gives immediate feedback (the prior version painted both `bg-surface-sunken`,
    # so an off item already looked selected on hover and the click produced no
    # visible change). Off-hover is the neutral `surface-sunken`; the selected (on)
    # state is the tinted `interactive-subtle` / `text-interactive` pairing (AAA,
    # same as badge `:secondary`). Hover is scoped to `data-[state=off]` so a
    # selected toggle keeps its tinted look on hover instead of reverting to neutral.
    BASE = "inline-flex items-center justify-center gap-2 rounded-md text-sm font-medium whitespace-nowrap " \
           "transition-[color,box-shadow] outline-none " \
           "data-[state=off]:hover:bg-surface-sunken data-[state=off]:hover:text-text-body " \
           "focus-ring " \
           "disabled:pointer-events-none disabled:opacity-50 " \
           "aria-invalid:border-danger-border aria-invalid:ring-danger  " \
           "data-[state=on]:bg-interactive-subtle data-[state=on]:text-interactive " \
           "[&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4"

    # AAA 2.5.5 target-size floor: every size renders >=44px tall (h-11 = 44px).
    # `sm` differs only in width/padding — its height is held at the 44px floor;
    # sub-44px heights are disallowed under AAA, so the historical h-8/h-9 are gone.
    SIZES = {
      default: "h-11 min-w-11 px-2",
      sm:      "h-11 min-w-11 px-1.5",
      lg:      "h-12 min-w-12 px-2.5"
    }.freeze

    def initialize(label = nil, pressed: false, size: :default, value: nil, **html_attrs)
      @label = label || html_attrs.delete(:label)
      @pressed = pressed
      @size = coerce_size(size.to_sym)
      @value = value
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:button,
        content.presence || @label,
        type: "button",
        "aria-pressed": @pressed.to_s,
        "data-state": @pressed ? "on" : "off",
        "data-controller": "toggle",
        "data-action": "click->toggle#toggle",
        value: @value,
        class: cn(BASE, SIZES.fetch(@size), @extra_class),
        **@html_attrs)
    end

    private

    # Fail loud on an unknown size in development/test so misuse is caught
    # immediately; fall back to :default in production so a bad size never
    # 500s a page. The Rails.respond_to?(:env) guard stays correct even when the Rails
    # module is defined but Rails.env isn't booted (the gem's Rails-less tests load
    # rails/generators, which defines Rails without Rails.env).
    def coerce_size(size)
      return size if SIZES.key?(size)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::ToggleComponent: unknown size #{size.inspect}. " \
          "Expected one of: #{SIZES.keys.join(", ")}."
      end

      :default
    end
  end
end
