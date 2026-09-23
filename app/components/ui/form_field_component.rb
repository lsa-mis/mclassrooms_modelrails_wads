# frozen_string_literal: true

module UI
  # Wraps a caption + control + optional hint and error into one AAA-correct field: it binds the `<label for>` to the control, gives the hint/error real ids that the control references via `aria-describedby`, and injects `invalid`/`required` into the control.
  # Usage, options and the accessibility contract: docs/components/form_field.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
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
