# frozen_string_literal: true

module UI
  # # Dialog
  #
  # A native `<dialog>` modal — focus-trapped, `aria-modal`, with native Escape
  # (cancel event) and `::backdrop`. The native element is chosen over a div so
  # focus-trapping and the inert background come for free. Behavior lives in the
  # `modal` Stimulus controller shipped alongside this component.
  #
  # ## Use when
  # - You need a focus-trapped modal for a confirmation, form, or detail overlay.
  # - You are building a custom wrapper (pass `wrapper: false` and own the
  #   `data-controller="modal"` element + trigger).
  #
  # ## Don't use when
  # - The action is a destructive non-GET — keep the submit in a `button_to` form;
  #   the dialog is the container, not the action mechanism.
  # - You need a non-blocking notification — use the toast / notification system.
  #
  # ## Accessibility contract
  # - **Guarantees:** native `<dialog>` semantics (`role="dialog"`, `aria-modal="true"`),
  #   `aria-labelledby` wired to the heading, `aria-describedby` when `description:` is
  #   given, an accessible close button, and focus trap + restore via the `modal`
  #   controller.
  # - **You supply:** a `title:` (required — it is the accessible name). With
  #   `wrapper: true` (default) the `trigger` slot is the open button; `wrapper: false`
  #   requires you to wire `data-controller="modal"` and a trigger yourself.
  class DialogComponent < ApplicationComponent
    renders_one :trigger
    renders_one :footer

    SIZES = { sm: "max-w-sm", md: "max-w-lg", lg: "max-w-2xl", full: "max-w-4xl" }.freeze

    PANEL = "relative w-full mx-auto rounded-lg bg-surface-overlay border border-border shadow-xl " \
            "max-h-[calc(100vh-3rem)] flex flex-col opacity-0"

    # title:       heading text (also the accessible name via aria-labelledby)
    # id:          dialog id (auto-generated if omitted)
    # size:        :sm | :md | :lg | :full
    # description: optional sub-text (wired via aria-describedby)
    # open:        render already-open (controller calls showModal on connect)
    # wrapper:     true (default) renders the modal controller wrapper + trigger slot
    #              (self-contained). false renders ONLY the <dialog> — for embedding in
    #              an existing data-controller="modal" structure (eases adoption of
    #              apps that already own the wrapper/trigger).
    # body_id:     id of the scrollable body element (defaults unique; pass a fixed id
    #              when Turbo Streams target it, e.g. "modal-body").
    def initialize(title:, id: nil, size: :md, description: nil, open: false,
                   wrapper: true, body_id: nil, **html_attrs)
      @title = title
      @id = id || "modal-#{SecureRandom.hex(4)}"
      @size = size.to_sym
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
      data = { controller: "modal" }
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
        class: "bg-transparent backdrop:bg-transparent w-full max-w-full p-4 sm:p-6"
      }
      attrs["aria-describedby"] = "#{@id}-description" if @description
      attrs
    end

    def panel
      content_tag(:div, safe_join([ header, body, footer_area ].compact),
        data: { modal_target: "panel" },
        class: cn(PANEL, SIZES.fetch(@size, SIZES[:md])))
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
