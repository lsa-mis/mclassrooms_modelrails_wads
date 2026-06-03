# frozen_string_literal: true

module UI
  # # Button
  #
  # The app's `.btn-*` system as a ViewComponent. Renders a real `<button type="button">`
  # — or an `<a>` when `href:` is given — with the AAA focus ring and the shared
  # `--form-input-height` touch target baked in.
  #
  # ## Use when
  # - You need a standalone action button, or a button-styled link, in **new** markup.
  #
  # ## Don't use when
  # - It's a **form submit** — use `f.submit` (the form builder already applies primary styling).
  # - It's a **destructive / non-GET action** (delete, revoke) — use `button_to`, which wraps a
  #   CSRF-protected form. This component renders only the button/link, never a form.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real interactive element, an AAA-tuned focus ring, and a 44px-minimum
  #   touch target.
  # - **You supply:** an accessible name — visible text/content, or an `aria-label:` for an
  #   icon-only button — and a valid `variant` (an unknown one raises in development).
  #
  # ## Variants
  # `primary` · `secondary` · `danger` · `text` · `text_interactive` · `text_danger`
  class ButtonComponentPreview < ViewComponent::Preview
    include UIHelper

    # The default, high-emphasis action. Aim for one primary per view.
    def primary; end

    # Neutral / secondary action, usually paired beside a primary.
    def secondary; end

    # Destructive *styling*. For a real delete, drive it with `button_to` and this variant's class.
    def danger; end

    # Low-emphasis inline action that reads like a link.
    def text_interactive; end

    # Button-styled link: pass `href:` and the component renders an `<a>`.
    def link; end

    # Edit `label` and `variant` live to explore the component.
    # @param label text
    # @param variant select [primary, secondary, danger, text, text_interactive, text_danger]
    def playground(label: "Button", variant: :primary)
      ui :button, label, variant: variant.to_sym
    end

    # ## Don't — icon-only button with no accessible name
    #
    # An icon-only button **must** carry an `aria-label:`, or screen-reader users hear nothing.
    # Prefer visible text; if the design is truly icon-only, pass a label:
    # `ui :button, "★", variant: :secondary, "aria-label": "Add to favorites"`.
    # @label Don't · icon-only without a label
    def dont_icon_only_without_label; end
  end
end
