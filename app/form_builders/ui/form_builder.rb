# frozen_string_literal: true

module UI
  # # FormBuilder
  #
  # Renders model-backed fields through UI::FormFieldComponent, wired to
  # ActiveModel::Errors.
  #
  # ## THE CONTRACT TO KNOW AT 2AM: no native `required` — ever
  #
  # Controls get `aria-required="true"` and the label gets a decorative mark,
  # but the HTML `required` attribute is never emitted on the builder path.
  # Why: one consistent, server-rendered error path. Native `required` lets the
  # browser block an empty submit with a transient bubble, so the error summary
  # and inline errors this builder exists to render never appear. If your
  # browser is NOT blocking an empty submit — that is this contract working.
  #
  # ## Subclass, don't edit
  #
  # Re-running `rails g modelrails_ui:add form_builder` OVERWRITES this file.
  # Put customizations in a subclass and point `default_form_builder` at it.
  # Supported override surface: the public Rails-named field helpers below.
  # Private helpers may change without notice between gem versions.
  class FormBuilder < ActionView::Helpers::FormBuilder
    CHECKBOX_CLASSES = "size-5 rounded border-border-strong text-interactive focus-ring"
    # One row = ONE ≥44px target (WCAG 2.5.5): the label wraps input + caption.
    CHECKBOX_ROW_CLASSES = "flex min-h-11 items-center gap-3 text-sm text-text-body"
    LEGEND_CLASSES = "text-sm font-medium text-text-body"

    def text_field(method, options = {})
      input_field(method, "text", options)
    end

    def email_field(method, options = {})
      input_field(method, "email", options)
    end

    def password_field(method, options = {})
      options = { autocomplete: "new-password" }.merge(options)
      input_field(method, "password", options)
    end

    def url_field(method, options = {})
      input_field(method, "url", options)
    end

    def tel_field(method, options = {})
      input_field(method, "tel", options)
    end

    def number_field(method, options = {})
      input_field(method, "number", options)
    end

    def date_field(method, options = {})
      input_field(method, "date", options)
    end

    def search_field(method, options = {})
      input_field(method, "search", options)
    end

    def text_area(method, options = {})
      options = { rows: 4 }.merge(options)
      wrapped_field(method, options) do |field, opts|
        name = opts.key?(:name) ? opts.delete(:name) : field_name(method)
        @template.render(UI::TextareaComponent.new(
          value: field_value(method, opts),
          name: name,
          class: opts.delete(:class),
          **control_kwargs(field),
          **opts
        ))
      end
    end

    def file_field(method, options = {})
      wrapped_field(method, options) do |field, opts|
        multiple = !!opts.delete(:multiple)
        name = opts.key?(:name) ? opts.delete(:name) : field_name(method, multiple: multiple)
        @template.render(UI::FileInputComponent.new(
          accept: opts.delete(:accept),
          multiple: multiple,
          name: name,
          class: opts.delete(:class),
          **control_kwargs(field),
          **opts
        ))
      end
    end

    # Native select via super, inside the wrapper. Chrome is the gem's
    # SelectComponent BASE + the `ui-select` customizable-select hook — never
    # the host-app-only `form-field` class. ARIA arrives via the field's
    # html_input_attrs translation (component kwargs are meaningless to Rails
    # tag helpers and would render as literal attributes).
    def select(method, choices = nil, options = {}, html_options = {}, &block)
      options = options.dup
      html_options = html_options.dup

      field_opts = {}
      field_opts[:label] = options.delete(:label) if options.key?(:label)
      field_opts[:help] = options.delete(:help) if options.key?(:help)
      # required in EITHER hash converts to aria-only — html_options is the
      # documented Rails signature, and passing it through to super would emit
      # native required, defeating the class-header contract. options wins
      # when both are given.
      field_opts[:required] = html_options.delete(:required) if html_options.key?(:required)
      field_opts[:required] = options.delete(:required) if options.key?(:required)
      field_opts[:id] = html_options.delete(:id) if html_options.key?(:id)

      wrapped_field(method, field_opts) do |field, _opts|
        aria = field.html_input_attrs
        caller_class = html_options.delete(:class)
        control_attrs = aria.merge(html_options) # caller options win on shared keys
        control_attrs[:class] = merge_classes("ui-select", UI::SelectComponent::BASE, caller_class)
        super(method, choices, options, control_attrs, &block)
      end
    end

    # Rails 8.1's canonical name is `checkbox`; `check_box` is an alias bound to
    # the ORIGINAL method, so overriding only check_box would let f.checkbox walk
    # straight past this builder. Define the canonical, re-alias the legacy name.
    def checkbox(method, options = {}, checked_value = "1", unchecked_value = "0")
      options = options.dup
      label_text = options.key?(:label) ? options.delete(:label) : default_label(method)
      hint = options.delete(:help)
      required = !!options.delete(:required)
      error = error_for(method)

      input_id =
        if options.key?(:id) then options[:id]
        elsif options[:multiple] then field_id(method, checked_value)
        else field_id(method)
        end
      options[:id] = input_id unless options.key?(:id)
      options[:class] = merge_classes(CHECKBOX_CLASSES, options[:class])
      options["aria-required"] = "true" if required
      options["aria-invalid"] = "true" if error

      # An explicit `id: nil` opts the caller out of id-derived wiring entirely:
      # skip describedby, and let the hint/error paragraphs render with no id
      # (below) rather than a degenerate "-error"/"-hint" nothing points at.
      error_id = "#{input_id}-error" if input_id && error
      hint_id = "#{input_id}-hint" if input_id && hint
      describedby = merge_classes(error_id, hint_id, options["aria-describedby"]).presence
      options["aria-describedby"] = describedby if describedby

      row = @template.content_tag(:label, class: CHECKBOX_ROW_CLASSES) do
        @template.safe_join([
          super(method, options, checked_value, unchecked_value),
          @template.content_tag(:span, label_text),
          (required_mark if required)
        ].compact)
      end
      @template.safe_join([
        row,
        (hint_paragraph(hint, id: hint_id) if hint),
        field_error_tag(method, id: input_id)
      ].compact)
    end
    alias_method :check_box, :checkbox

    def collection_checkboxes(method, collection, value_method, text_method, options = {}, html_options = {}, &block)
      collection_group(method, collection, value_method, text_method, options, html_options) do |opts, html_opts|
        super(method, collection, value_method, text_method, opts, html_opts) do |b|
          collection_row { @template.safe_join([ b.checkbox, @template.content_tag(:span, b.text) ]) }
        end
      end
    end
    alias_method :collection_check_boxes, :collection_checkboxes

    def collection_radio_buttons(method, collection, value_method, text_method, options = {}, html_options = {}, &block)
      collection_group(method, collection, value_method, text_method, options, html_options) do |opts, html_opts|
        super(method, collection, value_method, text_method, opts, html_opts) do |b|
          collection_row { @template.safe_join([ b.radio_button, @template.content_tag(:span, b.text) ]) }
        end
      end
    end

    def submit(value = nil, options = {})
      options = options.dup
      # Caller class: REPLACES the default (never merges): "btn-primary
      # btn-secondary" would leave stylesheet order to pick the winner.
      options[:class] = options[:class].presence || "btn-primary"
      super
    end

    # One-line shim over UI::ErrorSummaryComponent — the component is the real
    # surface (and the announcement mechanism; see its header). The shim adds
    # what only the builder knows: each error's field anchor via field_id.
    def error_summary(options = {})
      # respond_to? guard: an object-less builder (form_with url: sets object
      # to FALSE) has no errors surface — the summary is simply absent.
      return unless object.respond_to?(:errors) && object.errors.any?

      options = options.dup
      # Anchors are DERIVED default ids (Rails' field_id) — the summary renders
      # before the fields, so a call-site custom `id:` is unknowable here. The
      # call site opts such attributes out with `unlinked:` and their items
      # render as plain text, like :base errors (#121).
      unlinked = Array(options.delete(:unlinked)).map(&:to_sym)

      items = object.errors.map do |error|
        skip = error.attribute == :base || unlinked.include?(error.attribute.to_sym)
        href = skip ? nil : "##{field_id(error.attribute)}"
        { message: error.full_message, href: href }
      end
      @template.render(UI::ErrorSummaryComponent.new(items: items, **options))
    end

    private

    # Shared fieldset scaffolding for both collection helpers: legend, optional
    # hint, group-level aria-describedby ON THE FIELDSET (announced with the
    # group name on entry — widest AT support), per-input aria-invalid via
    # html_options (survives forms-mode arrival at a row), error paragraph via
    # the shared field_error_tag convention.
    def collection_group(method, _collection, _value_method, _text_method, options, html_options)
      options = options.dup
      html_options = html_options.dup
      legend_text = options.key?(:label) ? options.delete(:label) : default_label(method)
      hint = options.delete(:help)
      # Strip required from BOTH hashes: left in html_options it would emit
      # native required on every input in the group (same contract hole as
      # select's html_options path).
      required = !!options.delete(:required) | !!html_options.delete(:required)
      error = error_for(method)
      base_id = field_id(method)

      describedby = [ ("#{base_id}-error" if error), ("#{base_id}-hint" if hint) ].compact.join(" ").presence
      # Applies to both kinds — checkbox AND radio rows need CHECKBOX_CLASSES
      # (the shared 44px-target accent styling); a caller class is additive.
      html_options[:class] = merge_classes(CHECKBOX_CLASSES, html_options[:class])
      html_options["aria-invalid"] = "true" if error

      fieldset_attrs = { class: "space-y-2" }
      fieldset_attrs["aria-describedby"] = describedby if describedby

      @template.content_tag(:fieldset, **fieldset_attrs) do
        @template.safe_join([
          @template.content_tag(:legend, class: LEGEND_CLASSES) {
            @template.safe_join([ legend_text, (required_mark if required) ].compact)
          },
          (hint_paragraph(hint, id: "#{base_id}-hint") if hint),
          @template.content_tag(:div, class: "space-y-2") { yield(options, html_options) },
          field_error_tag(method, id: base_id)
        ].compact)
      end
    end

    def collection_row(&block)
      @template.content_tag(:label, class: CHECKBOX_ROW_CLASSES, &block)
    end

    def hint_paragraph(text, id:)
      @template.content_tag(:p, text, id: id,
        class: UI::FormFieldComponent::HINT_CLASSES, data: { slot: "description" })
    end

    def required_mark
      @template.content_tag(:span, "*", class: "text-danger", aria: { hidden: true })
    end

    # The shared wrapped-field cycle: extract the wrapper's options, render
    # FormFieldComponent, yield (field, remaining-options) for the control.
    # The field's id is passed INTO the component (never overridden on the
    # control afterwards) so label[for], hint id and error id stay bound.
    def wrapped_field(method, options)
      options = options.dup
      label = options.key?(:label) ? options.delete(:label) : default_label(method)
      hint = options.delete(:help)
      required = !!options.delete(:required)
      id = options.key?(:id) ? options.delete(:id) : field_id(method)

      field = UI::FormFieldComponent.new(
        label: label, hint: hint, error: error_for(method), required: required, id: id
      )
      @template.render(field) { yield(field, options) }
    end

    def input_field(method, type, options)
      wrapped_field(method, options) do |field, opts|
        name = opts.key?(:name) ? opts.delete(:name) : field_name(method)
        @template.render(UI::InputComponent.new(
          type: type,
          name: name,
          value: field_value(method, opts),
          class: opts.delete(:class),
          **control_kwargs(field),
          **opts
        ))
      end
    end

    # Component kwargs for a UI control: invalid/describedby from the field,
    # `required: false` ALWAYS (see the class header), aria-required set
    # directly. Spread caller opts AFTER this so caller options win.
    def control_kwargs(field)
      attrs = field.input_attrs
      kwargs = { id: attrs[:id], invalid: attrs[:invalid], describedby: attrs[:describedby], required: false }
      kwargs["aria-required"] = "true" if attrs[:required]
      kwargs
    end

    # Caller value (even explicit nil) wins; otherwise *_before_type_cast so a
    # failed cast re-renders what the user typed ("abc" in a number field must
    # not vanish on the 422 re-render); otherwise the reader.
    def field_value(method, opts)
      return opts.delete(:value) if opts.key?(:value)
      return nil unless object

      before_type_cast = :"#{method}_before_type_cast"
      if object.respond_to?(before_type_cast)
        object.public_send(before_type_cast)
      elsif object.respond_to?(method)
        object.public_send(method)
      end
    end

    def error_for(method)
      # respond_to?, not `&.`: form_with without a model sets object to FALSE
      # (not nil), which survives safe navigation and then raises on .errors.
      return nil unless object.respond_to?(:errors)

      object.errors[method]&.first
    end

    # Matches the wording ErrorSummary's full_messages use, so the name a user
    # hears in the summary is the name on the field.
    def default_label(method)
      if object && object.class.respond_to?(:human_attribute_name)
        object.class.human_attribute_name(method)
      else
        method.to_s.humanize
      end
    end

    # Shared with the checkbox/collection paths — same id + class conventions
    # as FormFieldComponent's own error paragraph (one decision, written once).
    # `id: nil` (an explicit checkbox `id: nil`) renders the paragraph with no
    # id rather than a degenerate "-error" — see the checkbox method's guard.
    def field_error_tag(method, id:)
      message = error_for(method)
      return if message.blank?

      @template.content_tag(:p, message, id: id && "#{id}-error",
        class: UI::FormFieldComponent::ERROR_CLASSES, data: { slot: "description" })
    end

    # Joins space-separated token lists generally — CSS classes AND
    # aria-describedby id lists both fit this shape. Don't "fix" this to be
    # class-specific; the describedby call sites depend on the same squish.
    def merge_classes(*classes)
      classes.compact.join(" ").squish
    end
  end
end
