# frozen_string_literal: true

module UI
  # # Copy
  #
  # A readonly value with a button that copies it to the clipboard — a share link, a
  # token, an ID — and confirms in two carriers: a check glyph and a pre-registered
  # status region that assistive technology announces. Failure is honest: the value is
  # selected and an assertive region says so; nothing ever claims a copy the browser
  # did not confirm.
  #
  # ## Use when
  # - The user needs to take a value with them: an invitation URL, an API token, an
  #   identifier they will paste somewhere else.
  #
  # ## Don't use when
  # - The value must be read or transcribed by a person rather than pasted — this
  #   single-line input scrolls a long value; a readable display is a different shape.
  # - The value is editable — this control is readonly by contract.
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<label for>` on the value; the trigger's accessible name is
  #   "<action> <label>" so the visible "Copy" is a substring in every state (WCAG 2.5.3)
  #   and never changes; two live regions — polite for success, assertive for failure —
  #   exist empty from first render; 44 px targets from the input and button cells;
  #   `focus-ring` outlines; no motion on the icon swap.
  # - **You supply:** `label:` as the NOUN for the value ("Invitation link") — it is
  #   interpolated into the accessible name and both announcements — and, if you
  #   translate, the four `modelrails_ui.copy.*` keys in your locale file.
  #
  # ## Strings
  # `modelrails_ui.copy.action` ("Copy", the visible text), `.button_label`
  # ("%{action} %{label}"), `.copied` ("Copied %{label} to the clipboard"), `.failed`
  # (a device-neutral instruction that names no key). Override per call with
  # `copy_label:` / `copied_label:` / `failed_label:`.
  class CopyComponent < ApplicationComponent
    WRAPPER = "space-y-1"
    ROW = "flex items-center gap-2"
    LABEL = "block text-sm font-medium text-text-heading"
    VALUE = "flex-1 min-w-0 font-mono text-sm"
    ICON = "size-4 shrink-0"
    STATUS = "text-xs text-text-body"
    ERROR = "text-xs text-danger"

    # Lucide `clipboard` and `check` (stroke, 24-box). Decorative: the status text is the
    # primary carrier, the glyph the second — never colour alone.
    CLIPBOARD_BODY = "M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"
    CHECK = "M20 6 9 17l-5-5"

    def initialize(value:, label:, label_hidden: false, id: nil,
                   copy_label: nil, copied_label: nil, failed_label: nil,
                   describedby: nil, autofocus: false, **html_attrs)
      @value = value
      @label = label
      @label_hidden = label_hidden
      @id = id || "copy-#{SecureRandom.hex(4)}"
      @copy_label = copy_label || I18n.t("modelrails_ui.copy.action", default: "Copy")
      @copied_label = copied_label ||
        I18n.t("modelrails_ui.copy.copied", label: label, default: "Copied %{label} to the clipboard")
      @failed_label = failed_label ||
        I18n.t("modelrails_ui.copy.failed", label: label,
          default: "Couldn't copy automatically. %{label} is selected — use your browser or device copy command.")
      @button_label = I18n.t("modelrails_ui.copy.button_label", action: @copy_label, label: label,
        default: "%{action} %{label}")
      @describedby = describedby
      @autofocus = autofocus
      @extra_class = html_attrs.delete(:class)
      @caller_data = html_attrs.delete(:data) || {}
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, **wrapper_attrs) do
        safe_join([ label_tag, row, regions ])
      end
    end

    private

    # The caller's `data:` is merged after the controller wiring so a passed-through
    # data attribute is never clobbered by the wiring — on a colliding key the caller
    # wins, deliberately (the toaster precedent: toaster_component.rb.tt:67-69,85).
    def wrapper_attrs
      data = {
        controller: "copy",
        slot: "control",
        state: "idle",
        copy_copied_value: @copied_label,
        copy_failed_value: @failed_label
      }.merge(@caller_data)
      @html_attrs.merge(class: cn(WRAPPER, @extra_class), data: data)
    end

    def label_tag
      content_tag(:label, @label, for: @id, class: @label_hidden ? "sr-only" : LABEL, data: { slot: "label" })
    end

    def row
      content_tag(:div, class: ROW) { safe_join([ value_input, trigger ]) }
    end

    # No `name`: a readonly value must never be submitted if a caller nests this in a form.
    def value_input
      render(UI::InputComponent.new(
        id: @id, type: "text", readonly: true, value: @value, class: VALUE,
        data: { slot: "copy-value", copy_target: "source" }
      ))
    end

    # describedby/autofocus belong on the trigger: a page that lands here should hear
    # the action and its warning, not the whole URL first.
    def trigger
      attrs = { "aria-label": @button_label, data: { slot: "copy-trigger", action: "copy#copy" } }
      attrs["aria-describedby"] = @describedby if @describedby.present?
      attrs[:autofocus] = true if @autofocus

      render(UI::ButtonComponent.new(variant: :outline, tone: :neutral, **attrs)) do
        safe_join([ copy_icon, success_icon, content_tag(:span, @copy_label) ])
      end
    end

    def copy_icon
      svg(target: "copyIcon", hidden: false) do
        safe_join([
          content_tag(:rect, nil, width: "8", height: "4", x: "8", y: "2", rx: "1", ry: "1"),
          content_tag(:path, nil, d: CLIPBOARD_BODY)
        ])
      end
    end

    def success_icon
      svg(target: "successIcon", hidden: true) { content_tag(:path, nil, d: CHECK) }
    end

    # [hidden] on an <svg> hides only through the stylesheet's [hidden]{display:none} rule
    # (Tailwind preflight ships it); the UA stylesheet leaves SVG inline.
    def svg(target:, hidden:, &)
      content_tag(:svg, capture(&),
        xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none",
        stroke: "currentColor", "stroke-width": "2", "stroke-linecap": "round", "stroke-linejoin": "round",
        "aria-hidden": "true", focusable: "false", hidden: hidden, class: ICON,
        data: { copy_target: target })
    end

    # Both regions exist, empty, from first render — a live region only announces
    # mutations into a node assistive technology is already watching. Polite for the
    # confirmation, assertive for a failure the user must not miss.
    def regions
      content_tag(:div, class: "min-h-5") do
        safe_join([
          content_tag(:p, nil, role: "status", "aria-live": "polite", "aria-atomic": "true",
            class: STATUS, data: { slot: "copy-status", copy_target: "status" }),
          content_tag(:p, nil, role: "alert", class: ERROR, data: { slot: "copy-error", copy_target: "error" })
        ])
      end
    end
  end
end
