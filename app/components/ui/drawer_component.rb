# frozen_string_literal: true

module UI
  # A native `<dialog>` bottom sheet — full-width, pinned to the bottom edge, sliding up on open.
  # Usage, options and the accessibility contract: docs/components/drawer.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class DrawerComponent < ApplicationComponent
    include UI::ModalChrome

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
      setup_modal_chrome(title: title, id: id, description: description, open: open,
        wrapper: wrapper, body_id: body_id, html_attrs: html_attrs)
    end

    private

    def wrapper_attrs
      base = super
      base[:data][:modal_enter_transform_value] = "translateY(0)"
      base[:data][:modal_leave_transform_value] = "translateY(100%)"
      base
    end

    def dialog_attrs
      attrs = {
        id: @id,
        role: "dialog",
        "aria-modal": "true",
        "aria-labelledby": "#{@id}-title",
        data: {
          modal_target: "dialog",
          controller: "drawer-drag",
          action: "drawer-drag:dismiss->modal#close " \
                  "pointermove@document->drawer-drag#move " \
                  "pointerup@document->drawer-drag#end " \
                  "pointercancel@document->drawer-drag#end"
        },
        class: "bg-transparent backdrop:bg-transparent m-0 mt-auto w-full max-w-full p-0"
      }
      attrs["aria-describedby"] = "#{@id}-description" if @description
      attrs
    end

    def panel
      content_tag(:div, safe_join([ drag_handle, header, body, footer_area ].compact),
        data: { modal_target: "panel", drawer_drag_target: "panel" },
        class: PANEL)
    end

    # aria-hidden and not focusable: dragging is pointer-only, so announcing a control
    # that keyboard and switch users cannot operate would promise something untrue. They
    # dismiss with Escape or the close button, which drag never replaces.
    def drag_handle
      content_tag(:div, content_tag(:div, nil, class: "h-1.5 w-12 rounded-full bg-surface-sunken"),
        class: "flex justify-center pt-3 pb-1 cursor-grab touch-none active:cursor-grabbing",
        "aria-hidden": "true",
        data: { action: "pointerdown->drawer-drag#start" })
    end
  end
end
