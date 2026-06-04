# frozen_string_literal: true

module UI
  # # Label
  #
  # The caption for a form control — renders a `<label>` and, via `for:`, binds it
  # to an input's `id` so clicking the caption focuses the control and a screen
  # reader announces the control's name.
  #
  # ## Use when
  # - You're captioning any form control (`input`, `textarea`, `select`, the
  #   form-control components). Pair `for:` with the control's `id`.
  #
  # ## Don't use when
  # - The control already self-labels (e.g. `checkbox`/`radio_group` render their
  #   own `<label>`) — don't wrap them a second time.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA-contrast caption text (`text-text-body`, a 7:1 token — no
  #   raw Tailwind color), and a `for=` association when you supply `for:`. A
  #   `required:` marker is a *decorative* `*` (`aria-hidden`): it never carries the
  #   requirement, which belongs on the input as `aria-required`/`required`.
  # - **You supply:** the caption text (arg or block) and, to bind it, the control's
  #   `id` via `for:`.
  #
  # A label is not an input: it has NO `invalid`/`aria-invalid`/`describedby` axis.
  class LabelComponent < ApplicationComponent
    # text-text-body is the AAA (7:1) body token — the caption must stay legible on
    # any surface, so the color is explicit here rather than inherited.
    BASE = "flex items-center gap-2 text-sm leading-none font-medium text-text-body select-none " \
           "group-data-[disabled=true]:pointer-events-none group-data-[disabled=true]:opacity-50 " \
           "peer-disabled:cursor-not-allowed peer-disabled:opacity-50"

    # The required marker is purely decorative — aria-hidden so it's never read out;
    # the requirement is conveyed on the control (aria-required), not the caption.
    REQUIRED_MARK = "text-danger"

    def initialize(text = nil, for: nil, required: false, **html_attrs)
      @text = text || html_attrs.delete(:label)
      @for = binding.local_variable_get(:for)
      @required = required
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:label,
        class: cn(BASE, @extra_class),
        for: @for,
        **@html_attrs) do
        safe_join([ content.presence || @text, required_mark ].compact)
      end
    end

    private

    def required_mark
      return unless @required

      content_tag(:span, "*", class: REQUIRED_MARK, aria: { hidden: true })
    end
  end
end
