# frozen_string_literal: true

module UI
  # # Sheet
  #
  # A native `<dialog>` side panel — pinned to a chosen edge and sliding in
  # from that edge. A flexible overlay for navigation, filters, and secondary
  # forms. Behavior lives in the `modal` Stimulus controller with per-side
  # slide transform values.
  #
  # ## Use when
  # - A side panel is the right pattern for navigation, filters, or secondary
  #   forms that slide in from a screen edge.
  # - You need a supplemental overlay anchored to the left, right, top, or
  #   bottom edge of the viewport.
  #
  # ## Don't use when
  # - A centered confirm gate is needed — use `dialog` with `role: :alertdialog`.
  # - A bottom sheet is the right pattern — use `drawer`.
  #
  # ## Accessibility contract
  # - **Guarantees:** native `<dialog>` with `role="dialog"` and `aria-modal="true"`,
  #   `aria-labelledby` wired to the heading, `aria-describedby` when `description:`
  #   is given, a 44px accessible close button (`btn-touch-target`), focus trap +
  #   restore via the `modal` controller, and native Escape via the controller's
  #   cancel handler.
  # - **You supply:** a `title:` (required — ViewComponent raises if omitted; it is
  #   the accessible name). Actions belong in the `footer` slot. With `wrapper: true`
  #   (default) the `trigger` slot is the open button; `wrapper: false` renders ONLY
  #   the `<dialog>` for embedding in an existing `data-controller="modal"` structure.
  #
  # Chrome lives in UI::ModalChrome — single owner.
  class SheetComponent < ApplicationComponent
    include UI::ModalChrome

    SIDES = {
      right:  "inset-y-0 right-0 ml-auto h-full w-3/4 max-w-sm rounded-l-lg border-l",
      left:   "inset-y-0 left-0 mr-auto h-full w-3/4 max-w-sm rounded-r-lg border-r",
      top:    "inset-x-0 top-0 mb-auto w-full max-h-[60vh] rounded-b-lg border-b",
      bottom: "inset-x-0 bottom-0 mt-auto w-full max-h-[60vh] rounded-t-lg border-t"
    }.freeze

    LEAVE_TRANSFORMS = {
      right:  "translateX(100%)",
      left:   "translateX(-100%)",
      top:    "translateY(-100%)",
      bottom: "translateY(100%)"
    }.freeze

    PANEL_BASE = "fixed bg-surface-overlay border border-border shadow-xl flex flex-col overflow-y-auto opacity-0".freeze

    # title:       heading text (also the accessible name via aria-labelledby) — required
    # id:          dialog id (auto-generated if omitted)
    # description: optional sub-text (wired via aria-describedby when given)
    # side:        which edge to pin the panel to (:right default | :left | :top | :bottom)
    # open:        render already-open (controller calls showModal on connect)
    # wrapper:     true (default) renders the modal controller wrapper + trigger slot
    #              (self-contained). false renders ONLY the <dialog> — for embedding in
    #              an existing data-controller="modal" structure (eases adoption of
    #              apps that already own the wrapper/trigger).
    # body_id:     id of the scrollable body element (defaults unique; pass a fixed id
    #              when Turbo Streams target it, e.g. "sheet-body").
    def initialize(title:, id: nil, description: nil, side: :right, open: false,
                   wrapper: true, body_id: nil, **html_attrs)
      @side = coerce_side(side.to_sym)
      setup_modal_chrome(title: title, id: id, description: description, open: open,
        wrapper: wrapper, body_id: body_id, html_attrs: html_attrs)
    end

    private

    def wrapper_attrs
      base = super
      base[:data][:modal_enter_transform_value] = enter_transform
      base[:data][:modal_leave_transform_value] = LEAVE_TRANSFORMS.fetch(@side)
      base
    end

    def enter_transform
      %i[left right].include?(@side) ? "translateX(0)" : "translateY(0)"
    end

    def dialog_attrs
      attrs = {
        id: @id,
        role: "dialog",
        "aria-modal": "true",
        "aria-labelledby": "#{@id}-title",
        data: { modal_target: "dialog" },
        class: "bg-transparent backdrop:bg-transparent m-0 p-0 max-w-full max-h-full"
      }
      attrs["aria-describedby"] = "#{@id}-description" if @description
      attrs
    end

    def panel
      content_tag(:div, safe_join([ header, body, footer_area ].compact),
        data: { modal_target: "panel" },
        class: cn(PANEL_BASE, SIDES.fetch(@side)))
    end

    # Fail loud on an unknown side in development/test so misuse is caught
    # immediately; fall back to :right in production so a bad side never
    # 500s a page. The Rails.respond_to?(:env) guard stays correct even when the Rails
    # module is defined but Rails.env isn't booted (the gem's Rails-less tests load
    # rails/generators, which defines Rails without Rails.env).
    def coerce_side(side)
      return side if SIDES.key?(side)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::SheetComponent: unknown side #{side.inspect}. " \
          "Expected one of: #{SIDES.keys.join(", ")}."
      end

      :right
    end
  end
end
