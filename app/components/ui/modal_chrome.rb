# frozen_string_literal: true

module UI
  # # ModalChrome
  #
  # The markup every native-`<dialog>` modal surface shares: the `data-controller="modal"`
  # wrapper + trigger slot, the `<dialog>` element and its ARIA wiring, the header/close
  # button, the scrollable body + description, and the footer slot. `dialog` (including
  # its `role: :alertdialog` confirm-gate mode), `sheet`, and `drawer` differ only in
  # panel shape (size classes vs. `role="alertdialog"` vs. side/offset classes) —
  # everything else is byte-identical chrome.
  #
  # ## Single-writer rationale
  # Before this concern, each of the four templates hand-copied the same eleven methods.
  # They drifted: sheet applied `@extra_class` twice (caught 2026-08-22) because a fix
  # landed in one copy and never propagated to its siblings. `ModalChrome` makes drift
  # structurally impossible — there is exactly one place these methods can be defined,
  # enforced by `test/test_modal_chrome_ownership.rb`: no family template may redefine a
  # chrome method, and the concern must define every one of them.
  #
  # A component includes this module, calls `renders_one :trigger; renders_one :footer`
  # (done via `included` below — the includer does not repeat it), and calls
  # `setup_modal_chrome` from its own `initialize` with its own variant-specific kwargs
  # (`size:`, `side:`, `role:`, ...) handled separately.
  module ModalChrome
    def self.included(base)
      base.renders_one :trigger
      base.renders_one :footer

      # `call` needs base.class_eval, not a plain module method: ViewComponent's compiler
      # looks for a `call` template method by scanning `component.ancestors` MINUS
      # `component.included_modules` (view_component/compiler.rb#generate_templates) — a
      # `call` reachable only through an included module is invisible to it and every
      # render raises "Couldn't find a template file or inline render method". class_eval
      # defines `call` directly on the includer (dialog/sheet/drawer), which
      # satisfies that scan; its body still resolves trigger_area/dialog_tag/etc. through
      # ordinary Ruby method lookup, so those stay plain module methods below — only `call`
      # gets this special case.
      base.class_eval do
        def call
          return dialog_tag unless @wrapper

          content_tag(:div, **wrapper_attrs) do
            safe_join([ trigger_area, dialog_tag ].compact)
          end
        end
      end
    end

    private

    # Shared initializer half: every modal surface calls this from its own
    # initialize with its variant-specific kwargs handled separately.
    # body_id derives from id unconditionally — it is the Turbo Stream target
    # contract. A wrapper:true surface without an explicit id gets a random id
    # and therefore an untargetable body: fail loud in dev/test (streams fail
    # SILENTLY on missing targets in production), mirroring sheet's
    # coerce_side pattern. Rails.respond_to?(:env) (not just defined?(Rails)) matters:
    # the gem's own structural test lane loads "rails/generators" for unrelated generator
    # specs in the same process, which defines the Rails module WITHOUT Rails.env —
    # defined?(Rails) alone would raise NoMethodError there.
    def setup_modal_chrome(title:, id: nil, description: nil, open: false,
                           wrapper: true, body_id: nil, html_attrs: {})
      @title = title
      if id.nil? && wrapper && body_id.nil? && defined?(Rails) && Rails.respond_to?(:env) &&
          (Rails.env.development? || Rails.env.test?)
        raise ArgumentError,
          "#{self.class.name}: wrapper: true without an explicit id: (or body_id:) " \
          "generates a random body id — Turbo Streams aimed at it silently no-op. " \
          "Pass id: (recommended) or body_id:."
      end
      @id = id || "modal-#{SecureRandom.hex(4)}"
      @description = description
      @open = open
      @wrapper = wrapper
      @body_id = body_id || "#{@id}-body"
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

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

    def header
      content_tag(:header, class: "flex items-center justify-between px-6 py-4 border-b border-border shrink-0", data: { slot: "header" }) do
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
        data: { action: "click->modal#close", slot: "close" },
        class: "btn-touch-target rounded-md -m-2 hover:bg-surface-sunken text-text-muted hover:text-text-body focus-ring")
    end

    def body
      content_tag(:div, safe_join([ description_tag, content ].compact),
        id: @body_id, data: { slot: "body" }, class: "px-6 py-4 overflow-y-auto flex-1")
    end

    def description_tag
      return unless @description

      content_tag(:p, @description, id: "#{@id}-description", class: "text-sm text-text-muted mb-4")
    end

    def footer_area
      return unless footer?

      content_tag(:div, footer, class: "flex justify-end gap-2 px-6 py-4 border-t border-border shrink-0", data: { slot: "footer" })
    end

    def close_label
      I18n.t("modelrails_ui.modal.close", default: [ :"modals.close", "Close" ])
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
