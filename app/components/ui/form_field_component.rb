# frozen_string_literal: true

module UI
  # # Form Field
  #
  # Wraps a caption + control + optional hint and error into one AAA-correct field:
  # it binds the `<label for>` to the control, gives the hint/error real ids that the
  # control references via `aria-describedby`, and injects `invalid`/`required` into
  # the control. The control arrives as a block, so the component yields its field
  # context (`input_attrs`) and the caller spreads it onto any control:
  #
  #   <%= ui :form_field, label: "Email", hint: "We'll never share it.",
  #         error: @user.errors[:email].first, required: true do |f| %>
  #     <%= ui :input, type: "email", name: "user[email]", **f.input_attrs %>
  #   <% end %>
  #
  # ## Use when
  # - You're composing a single labelled field by hand (a one-off form, or a control
  #   the form builder (`UI::FormBuilder`) doesn't cover). For model-backed forms,
  #   prefer the builder — it already does this wiring.
  #
  # ## Accessibility contract
  # - **Guarantees:** a `<label for=id>` bound to the control; hint/error rendered with
  #   ids `#{id}-hint`/`#{id}-error`; and `input_attrs` carrying `id` +
  #   `describedby` (**error-first**, then hint — `[error, hint]` — front-loading the
  #   correction for AT users now that the hint sits below the control) + `invalid`
  #   (on error) + `required`. The required marker is a decorative aria-hidden `*` on
  #   the Label — the caption never carries the requirement.
  # - **No live region:** the error `<p>` is plain markup, not `role="alert"`. A
  #   field-level live region never fires on a server-rendered response — the region
  #   has to exist before its content changes to announce anything. The focused
  #   `ErrorSummary` component is the actual announcement mechanism.
  # - **You supply:** the control inside the block, spread with `**f.input_attrs` so it
  #   adopts the field's id and aria wiring. Rendering a native (non-ViewComponent)
  #   control instead? Use `html_input_attrs`, which translates the same wiring into
  #   real `aria-*` attributes.
  # - **Id fallback:** without an explicit `id:`, the id is derived from `label` (so
  #   repeated renders of the same field agree, which Turbo morphing and HTML
  #   snapshot tests depend on) — pass explicit ids when two fields on one page share
  #   a label. `UI::FormBuilder` always supplies an id, so this only matters when
  #   composing a field by hand.
  class FormFieldComponent < ApplicationComponent
    # data-slot adjacency rhythm (the Catalyst model): label→control 12px,
    # control→description 8px, description→description 4px. Self-contained Tailwind
    # arbitrary variants keyed on the children's data-slot — no host CSS needed.
    WRAPPER = "[&>[data-slot=label]+[data-slot=control]]:mt-3 " \
              "[&>[data-slot=control]+[data-slot=description]]:mt-2 " \
              "[&>[data-slot=description]+[data-slot=description]]:mt-1"

    # Shared with the form builder's checkbox/collection paths — the id + hint/error
    # paragraph convention is one decision written once, even where markup differs.
    HINT_CLASSES = "text-sm text-text-muted"
    ERROR_CLASSES = "text-sm text-danger"

    # Prefix for label-derived ids. Deliberately NOT a usable id on its own: with
    # neither an explicit id nor a label there is nothing to wire, and a constant
    # fallback id would collide as soon as a page rendered two instances.
    FALLBACK_PREFIX = "form_field"

    def initialize(label: nil, hint: nil, error: nil, required: false, **html_attrs)
      @label = label
      @hint = hint
      @error = error
      @required = required
      @id = html_attrs.key?(:id) ? html_attrs.delete(:id) : fallback_id
      @describedby = @id && [ ("#{@id}-error" if @error.present?), ("#{@id}-hint" if @hint.present?) ].compact.join(" ").presence
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    # The wiring the slotted control must spread (`**f.input_attrs`): id +
    # aria-describedby (hint/error ids) + invalid + required. Mirrors exactly what
    # the form builder (`UI::FormBuilder`) injects into the controls it renders itself.
    def input_attrs
      { id: @id, describedby: @describedby, invalid: @error.present?, required: @required }
    end

    # input_attrs translated to real HTML attributes, for native (non-ViewComponent)
    # controls — the builder's `select` path, and any future raw control. Component
    # kwargs (describedby:/invalid:/required:) are meaningless to Rails tag helpers;
    # spreading input_attrs into one emits literal `describedby=` garbage.
    def html_input_attrs
      attrs = {}
      attrs[:id] = @id if @id
      attrs["aria-describedby"] = @describedby if @describedby
      attrs["aria-invalid"] = "true" if @error.present?
      attrs["aria-required"] = "true" if @required
      attrs
    end

    def call
      content_tag(:div, class: cn(WRAPPER, @extra_class), **@html_attrs) do
        safe_join([
          field_label,
          content_tag(:div, content, data: { slot: "control" }),
          hint_tag,
          error_tag
        ].compact)
      end
    end

    private

    # Deterministic id fallback so a render doesn't grow a fresh DOM id every time
    # (breaks Turbo morphing and any HTML-snapshot test). Derived from the label so
    # two calls with the same label agree; two same-label fields on one page still
    # need an explicit id: from the caller. UI::FormBuilder always passes one.
    def fallback_id
      return nil if @label.blank?

      slug = @label.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      slug.presence && "#{FALLBACK_PREFIX}_#{slug}"
    end

    # The caption, via the Label primitive: a real `for=` association + the decorative
    # aria-hidden `*` required mark. data-slot=label drives the adjacency spacing.
    def field_label
      return unless @label

      render(UI::LabelComponent.new(@label, for: @id, required: @required, data: { slot: "label" }))
    end

    def hint_tag
      return unless @hint.present?

      content_tag(:p, @hint, id: @id && "#{@id}-hint", class: HINT_CLASSES, data: { slot: "description" })
    end

    def error_tag
      return unless @error.present?

      content_tag(:p, @error, id: @id && "#{@id}-error", class: ERROR_CLASSES, data: { slot: "description" })
    end
  end
end
