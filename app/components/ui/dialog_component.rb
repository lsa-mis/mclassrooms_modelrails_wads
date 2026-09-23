# frozen_string_literal: true

module UI
  # A native `<dialog>` modal — focus-trapped, `aria-modal`, with native Escape (cancel event) and `::backdrop`.
  # Usage, options and the accessibility contract: docs/components/dialog.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class DialogComponent < ApplicationComponent
    include UI::ModalChrome

    SIZES = { sm: "max-w-sm", md: "max-w-lg", lg: "max-w-2xl", full: "max-w-4xl" }.freeze

    ROLES = %i[dialog alertdialog].freeze

    # No `scale-95` rest class: TW4 compiles it to the separate scale:
    # property, which COMPOSES with the modal controller's inline
    # transform:scale(1) instead of being overridden — open panels rested 5%
    # shrunken (a11y gate, 2026-07-13). The controller sets the pre-open
    # transform inline; the closed <dialog> hides the panel regardless.
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
    # role:        :dialog (default) | :alertdialog — an assertive confirm gate that
    #              screen readers announce immediately, capped at max-w-md regardless
    #              of size: (v0.11.0 folded the standalone confirm-dialog component
    #              into this role).
    def initialize(title:, id: nil, size: :md, description: nil, open: false,
                   wrapper: true, body_id: nil, role: :dialog, **html_attrs)
      @size = size.to_sym
      @role = coerce_role(role.to_sym)
      setup_modal_chrome(title: title, id: id, description: description, open: open,
        wrapper: wrapper, body_id: body_id, html_attrs: html_attrs)
    end

    private

    def dialog_attrs
      attrs = {
        id: @id,
        role: @role.to_s,
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
        class: @role == :alertdialog ? cn(PANEL, "max-w-md") : cn(PANEL, SIZES.fetch(@size, SIZES[:md])))
    end

    # Fail loud on an unknown role in development/test so misuse is caught
    # immediately; fall back to :dialog in production so a bad role never
    # 500s a page. Same shape as sheet's coerce_side — see its comment for the
    # Rails.respond_to?(:env) guard rationale.
    def coerce_role(role)
      return role if ROLES.include?(role)

      unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env.production?
        raise ArgumentError,
          "UI::DialogComponent: unknown role #{role.inspect}. " \
          "Expected one of: #{ROLES.join(", ")}."
      end

      :dialog
    end
  end
end
