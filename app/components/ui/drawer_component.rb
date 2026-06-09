# frozen_string_literal: true

module UI
  # # Drawer
  #
  # A native `<dialog>` bottom sheet — full-width, pinned to the bottom edge,
  # sliding up on open. A lightweight mobile-friendly overlay for secondary
  # actions and supplemental content. Behavior lives in the `modal` Stimulus
  # controller with slide-up/down transform values.
  #
  # ## Use when
  # - A bottom sheet is the right pattern for mobile-friendly secondary actions
  #   or content that slides in from the bottom edge.
  # - You need a supplemental overlay that doesn't require center-stage emphasis.
  #
  # ## Don't use when
  # - A centered confirm gate is needed — use `alert_dialog`.
  # - A side panel is needed — use `sheet`.
  #
  # ## Accessibility contract
  # - **Guarantees:** native `<dialog>` with `role="dialog"` and `aria-modal="true"`,
  #   `aria-labelledby` wired to the heading, `aria-describedby` when `description:`
  #   is given, a 44px accessible close button (`btn-touch-target`), focus trap +
  #   restore via the `modal` controller, and native Escape via the controller's
  #   cancel handler. The drag handle is purely decorative (`aria-hidden`).
  # - **You supply:** a `title:` (required — ViewComponent raises if omitted; it is
  #   the accessible name). Actions belong in the `footer` slot. With `wrapper: true`
  #   (default) the `trigger` slot is the open button; `wrapper: false` renders ONLY
  #   the `<dialog>` for embedding in an existing `data-controller="modal"` structure.
  class DrawerComponent < ApplicationComponent
    renders_one :trigger
    renders_one :footer

    PANEL = "relative w-full rounded-t-xl bg-surface-overlay border-t border-border shadow-xl " \
            "max-h-[calc(100vh-3rem)] flex flex-col opacity-0 translate-y-full"

    # title:       heading text (also the accessible name via aria-labelledby) — required
    # id:          dialog id (auto-generated if omitted)
    # description: optional sub-text (wired via aria-describedby when given)
    # open:        render already-open (controller calls showModal on connect)
    # wrapper:     true (default) renders the modal controller wrapper + trigger slot
    #              (self-contained). false renders ONLY the <dialog> — for embedding in
    #              an existing data-controller="modal" structure (eases adoption of
    #              apps that already own the wrapper/trigger).
    # body_id:     id of the scrollable body element (defaults unique; pass a fixed id
    #              when Turbo Streams target it, e.g. "drawer-body").
    def initialize(title:, id: nil, description: nil, open: false,
                   wrapper: true, body_id: nil, **html_attrs)
      @title = title
      @id = id || "drawer-#{SecureRandom.hex(4)}"
      @description = description
      @open = open
      @wrapper = wrapper
      @body_id = body_id || "#{@id}-body"
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      return dialog_tag unless @wrapper

      content_tag(:div, **wrapper_attrs) do
        safe_join([ trigger_area, dialog_tag ].compact)
      end
    end

    private

    def wrapper_attrs
      data = {
        controller: "modal",
        modal_enter_transform_value: "translateY(0)",
        modal_leave_transform_value: "translateY(100%)"
      }
      data[:modal_open_value] = "true" if @open
      { data: data, class: cn("inline", @extra_class) }.merge(@html_attrs)
    end

    def trigger_area
      return unless trigger?

      content_tag(:span, trigger, class: "contents", data: { action: "click->modal#open" })
    end

    def dialog_tag
      content_tag(:dialog, panel, **dialog_attrs)
    end

    def dialog_attrs
      attrs = {
        id: @id,
        role: "dialog",
        "aria-modal": "true",
        "aria-labelledby": "#{@id}-title",
        data: { modal_target: "dialog" },
        class: "bg-transparent backdrop:bg-transparent m-0 mt-auto w-full max-w-full p-0"
      }
      attrs["aria-describedby"] = "#{@id}-description" if @description
      attrs
    end

    def panel
      content_tag(:div, safe_join([ drag_handle, header, body, footer_area ].compact),
        data: { modal_target: "panel" },
        class: PANEL)
    end

    def drag_handle
      content_tag(:div, content_tag(:div, nil, class: "h-1.5 w-12 rounded-full bg-surface-sunken"),
        class: "flex justify-center pt-3 pb-1",
        "aria-hidden": "true")
    end

    def header
      content_tag(:header, class: "flex items-center justify-between px-6 py-4 border-b border-border shrink-0") do
        safe_join([
          content_tag(:h2, @title, id: "#{@id}-title", class: "text-lg font-semibold text-text-heading"),
          close_button
        ])
      end
    end

    def close_button
      content_tag(:button, close_icon,
        type: "button",
        "aria-label": close_label,
        data: { action: "click->modal#close" },
        class: "btn-touch-target rounded-md -m-2 hover:bg-surface-sunken text-text-muted hover:text-text-body focus-ring")
    end

    def body
      content_tag(:div, safe_join([ description_tag, content ].compact),
        id: @body_id, class: "px-6 py-4 overflow-y-auto flex-1")
    end

    def description_tag
      return unless @description

      content_tag(:p, @description, id: "#{@id}-description", class: "text-sm text-text-muted mb-4")
    end

    def footer_area
      return unless footer?

      content_tag(:div, footer, class: "flex justify-end gap-2 px-6 py-4 border-t border-border shrink-0")
    end

    def close_label
      I18n.t("modals.close", default: "Close")
    end

    def close_icon
      if helpers.respond_to?(:icon)
        helpers.icon(:x_mark, size: :md)
      else
        raw('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" ' \
            'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' \
            '<path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>')
      end
    end
  end
end
