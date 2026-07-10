class TailwindFormBuilder < ActionView::Helpers::FormBuilder
  # Design tokens consumed: --form-input-height (see app/assets/tailwind/tokens/_spacing.css).
  # The same token drives .btn-touch-target so inputs and buttons align at one source.

  LABEL_CLASSES = "block text-sm font-medium text-text-body".freeze
  ERROR_LABEL_CLASSES = "block text-sm font-medium text-danger".freeze
  HELP_TEXT_CLASSES = "text-sm text-text-muted".freeze
  ERROR_MESSAGE_CLASSES = "text-sm text-danger".freeze

  CHECKBOX_CLASSES = "size-5 rounded border-border-strong text-interactive focus-ring mt-0.5".freeze

  def text_field(method, options = {})
    field_wrapper(method, options) do |opts|
      ui_input(method, "text", opts)
    end
  end

  def email_field(method, options = {})
    field_wrapper(method, options) do |opts|
      ui_input(method, "email", opts)
    end
  end

  def password_field(method, options = {})
    options[:autocomplete] ||= "new-password"
    field_wrapper(method, options) do |opts|
      ui_input(method, "password", opts)
    end
  end

  def url_field(method, options = {})
    field_wrapper(method, options) do |opts|
      ui_input(method, "url", opts)
    end
  end

  def tel_field(method, options = {})
    field_wrapper(method, options) do |opts|
      ui_input(method, "tel", opts)
    end
  end

  def number_field(method, options = {})
    field_wrapper(method, options) do |opts|
      ui_input(method, "number", opts)
    end
  end

  def date_field(method, options = {})
    field_wrapper(method, options) do |opts|
      ui_input(method, "date", opts)
    end
  end

  def search_field(method, options = {})
    field_wrapper(method, options) do |opts|
      ui_input(method, "search", opts)
    end
  end

  def text_area(method, options = {})
    options[:rows] ||= 4
    field_wrapper(method, options) do |opts|
      ui_textarea(method, opts)
    end
  end

  def select(method, choices = nil, options = {}, html_options = {}, &block)
    wrapper_opts = options.extract!(:label, :required, :help)
    field_wrapper(method, wrapper_opts) do |_|
      super(method, choices, options, html_options.merge(select_html_options(method, wrapper_opts)), &block)
    end
  end

  def check_box(method, options = {}, checked_value = "1", unchecked_value = "0")
    label_text = options.delete(:label) || method.to_s.humanize
    @template.content_tag(:div, class: "flex items-start gap-3") do
      super(method, options.merge(class: merge_classes(CHECKBOX_CLASSES, options[:class])), checked_value, unchecked_value) +
        @template.label_tag(field_id(method), label_text, class: "text-sm text-text-body")
    end
  end

  def collection_check_boxes(method, collection, value_method, text_method, options = {}, html_options = {}, &block)
    label_text = options.delete(:label) || method.to_s.humanize
    @template.content_tag(:fieldset, class: "space-y-2") do
      @template.content_tag(:legend, label_text, class: LABEL_CLASSES) +
        @template.content_tag(:div, class: "space-y-2") do
          super(method, collection, value_method, text_method, options, html_options.merge(class: CHECKBOX_CLASSES)) { |b|
            @template.content_tag(:div, class: "flex items-center gap-3") do
              b.check_box + b.label(class: "text-sm text-text-body")
            end
          }
        end +
        field_error(method)
    end
  end

  def collection_radio_buttons(method, collection, value_method, text_method, options = {}, html_options = {}, &block)
    label_text = options.delete(:label) || method.to_s.humanize
    @template.content_tag(:fieldset, class: "space-y-2") do
      @template.content_tag(:legend, label_text, class: LABEL_CLASSES) +
        @template.content_tag(:div, class: "space-y-2") do
          super(method, collection, value_method, text_method, options, html_options) { |b|
            @template.content_tag(:div, class: "flex items-center gap-3") do
              b.radio_button(class: CHECKBOX_CLASSES) + b.label(class: "text-sm text-text-body")
            end
          }
        end +
        field_error(method)
    end
  end

  def file_field(method, options = {})
    field_wrapper(method, options) do |opts|
      ui_file(method, opts)
    end
  end

  def submit(value = nil, options = {})
    super(value, options.merge(class: merge_classes("btn-primary", options[:class])))
  end

  def error_summary(options = {})
    return nil unless object&.errors&.any?

    count = object.errors.count
    @template.content_tag(:div, role: "alert",
                          class: "rounded-lg border border-danger-border bg-danger-surface p-4") do
      @template.content_tag(:div, class: "flex items-start gap-3") do
        @template.icon(:exclamation_circle, size: :md, class: "text-danger-icon shrink-0 mt-0.5") +
          @template.content_tag(:div) do
            @template.content_tag(:h2, I18n.t("errors.form_errors", count: count),
                                  class: "text-sm font-semibold text-danger") +
              @template.content_tag(:ul, class: "mt-2 list-disc list-inside text-sm text-danger") do
                object.errors.full_messages.map { |msg|
                  @template.content_tag(:li, msg)
                }.join.html_safe
              end
          end
      end
    end
  end

  private

  def field_wrapper(method, options, &block)
    label_text = options.delete(:label)
    required = options.delete(:required)
    help = options.delete(:help)

    # Re-inject required and help so ui_input/ui_textarea/ui_file can use them for ARIA attrs.
    options[:required] = required if required
    options[:help] = help if help

    @template.content_tag(:div, class: "space-y-2") do
      build_label(method, label_text, required: required) +
        (help ? build_help(method, help) : "".html_safe) +
        yield(options) +
        field_error(method)
    end
  end

  def build_label(method, label_text, required: false)
    text = label_text || method.to_s.humanize
    css = has_errors?(method) ? ERROR_LABEL_CLASSES : LABEL_CLASSES

    content = if required
                "#{text} #{@template.content_tag(:span, "*", class: "text-danger")}".html_safe
    else
                text
    end

    @template.label_tag(field_id(method), content, class: css, for: field_id(method))
  end

  def build_help(method, text)
    @template.content_tag(:p, text, id: "#{field_id(method)}-help", class: HELP_TEXT_CLASSES)
  end

  def field_error(method)
    return "".html_safe unless has_errors?(method)

    message = object.errors[method].first
    @template.content_tag(:p, message, id: "#{field_id(method)}-error",
                          role: "alert", class: ERROR_MESSAGE_CLASSES)
  end

  def select_html_options(method, wrapper_opts)
    {
      # `ui-select` is the hook for the customizable-select picker styling
      # (application.css `@supports (appearance: base-select)`). App dropdowns are
      # native form-builder selects, so the hook rides here, not just on UI::Select;
      # `form-field` keeps the field chrome. No-op in browsers without base-select.
      class: "form-field ui-select",
      id: field_id(method)
    }.merge(aria_attributes(method, wrapper_opts))
  end

  def aria_attributes(method, options)
    attrs = {}
    attrs[:"aria-required"] = "true" if options[:required]
    attrs[:"aria-invalid"] = "true" if has_errors?(method)

    describedby = []
    describedby << "#{field_id(method)}-help" if options[:help]
    describedby << "#{field_id(method)}-error" if has_errors?(method)
    attrs[:"aria-describedby"] = describedby.join(" ") if describedby.any?

    attrs
  end

  # Render the form control via UI::InputComponent (the shared component system),
  # while this builder retains ownership of the label, help text, error message,
  # and ARIA wiring (via field_wrapper). The component reproduces the app's field
  # styling exactly, so this delegation is visually invisible.
  def ui_input(method, type, opts)
    required = opts.delete(:required)
    help = opts.delete(:help)
    custom_class = opts.delete(:class)
    value = opts.key?(:value) ? opts.delete(:value) : current_field_value(method)
    id = opts.delete(:id) || field_id(method)
    name = opts.delete(:name) || field_name(method)
    # Advertise required state via aria-required ONLY (component required: false), to
    # match the app's existing fields: a native HTML `required` would let the browser
    # block empty submits before they reach the server, suppressing the server-rendered
    # error summary/inline errors (see spec/system/registration_validation_spec.rb).
    opts["aria-required"] = "true" if required

    @template.render(UI::InputComponent.new(
      type: type,
      required: false,
      invalid: has_errors?(method),
      describedby: ui_describedby(method, help: help),
      id: id,
      name: name,
      value: value,
      class: custom_class,
      **opts
    ))
  end

  def ui_textarea(method, opts)
    required = opts.delete(:required)
    help = opts.delete(:help)
    custom_class = opts.delete(:class)
    value = opts.key?(:value) ? opts.delete(:value) : current_field_value(method)
    id = opts.delete(:id) || field_id(method)
    name = opts.delete(:name) || field_name(method)
    # aria-required only — same parity reasoning as ui_input above.
    opts["aria-required"] = "true" if required

    @template.render(UI::TextareaComponent.new(
      value: value,
      required: false,
      invalid: has_errors?(method),
      describedby: ui_describedby(method, help: help),
      id: id,
      name: name,
      class: custom_class,
      **opts
    ))
  end

  def ui_file(method, opts)
    required = opts.delete(:required)
    help = opts.delete(:help)
    custom_class = opts.delete(:class)
    accept = opts.delete(:accept)
    multiple = opts.delete(:multiple)
    id = opts.delete(:id) || field_id(method)
    name = opts.delete(:name) || field_name(method, multiple: !!multiple)

    @template.render(UI::FileInputComponent.new(
      accept: accept,
      multiple: !!multiple,
      required: !!required,
      invalid: has_errors?(method),
      describedby: ui_describedby(method, help: help),
      id: id,
      name: name,
      class: custom_class,
      **opts
    ))
  end

  def ui_describedby(method, help:)
    ids = []
    ids << "#{field_id(method)}-help" if help
    ids << "#{field_id(method)}-error" if has_errors?(method)
    ids.join(" ").presence
  end

  def current_field_value(method)
    object.respond_to?(method) ? object.public_send(method) : nil
  end

  def has_errors?(method)
    object&.errors&.[](method)&.any? || false
  end

  # Mirror Rails' own namespaced id generation so labels/help/error ids
  # computed here match the input ids Rails emits via `super` (check_box,
  # rich_text_area, etc.). Without the namespace, a `form_with namespace:`
  # form (e.g. the per-context notes forms, whole-branch review I-1) gives
  # every input a namespaced id while this helper hands the matching label a
  # bare `note_body`/`note_alert` `for` — orphaning the label (WCAG label
  # association failure). `options[:namespace]` is nil for ordinary forms, so
  # their ids are unchanged.
  def field_id(method)
    [ options[:namespace], @object_name, method ].compact.join("_")
  end

  def merge_classes(*classes)
    classes.compact.join(" ").squish
  end
end
