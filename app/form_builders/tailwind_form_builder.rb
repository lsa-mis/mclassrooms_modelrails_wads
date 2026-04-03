class TailwindFormBuilder < ActionView::Helpers::FormBuilder
  # State-independent base classes (layout, spacing, shape)
  FIELD_BASE = "block w-full rounded-md border px-3 py-2 placeholder:text-text-muted focus:outline-none focus:ring-2 min-h-[44px]"

  # State-dependent classes — applied exclusively (normal OR error, never both)
  FIELD_NORMAL = "border-border-strong bg-surface-raised text-text-heading focus:ring-interactive-focus"
  FIELD_ERROR = "border-danger ring-2 ring-danger bg-danger-surface text-danger focus:ring-danger"

  LABEL_CLASSES = "block text-sm font-medium text-text-body"
  ERROR_LABEL_CLASSES = "block text-sm font-medium text-danger"
  HELP_TEXT_CLASSES = "text-sm text-text-muted"
  ERROR_MESSAGE_CLASSES = "text-sm text-danger"

  SUBMIT_CLASSES = "min-h-[44px] inline-flex items-center justify-center px-4 rounded-md bg-interactive hover:bg-interactive-hover text-text-on-interactive font-medium focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-interactive-focus cursor-pointer"

  CHECKBOX_CLASSES = "size-5 rounded border-border-strong text-interactive focus:ring-2 focus:ring-interactive-focus mt-0.5"

  FILE_FIELD_CLASSES = "block w-full text-sm text-text-body file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-medium file:bg-interactive file:text-text-on-interactive hover:file:bg-interactive-hover file:cursor-pointer file:min-h-[44px]"

  def text_field(method, options = {})
    field_wrapper(method, options) do |opts|
      super(method, field_options(method, opts))
    end
  end

  def email_field(method, options = {})
    field_wrapper(method, options) do |opts|
      super(method, field_options(method, opts))
    end
  end

  def password_field(method, options = {})
    options[:autocomplete] ||= "new-password"
    field_wrapper(method, options) do |opts|
      super(method, field_options(method, opts))
    end
  end

  def url_field(method, options = {})
    field_wrapper(method, options) do |opts|
      super(method, field_options(method, opts))
    end
  end

  def tel_field(method, options = {})
    field_wrapper(method, options) do |opts|
      super(method, field_options(method, opts))
    end
  end

  def number_field(method, options = {})
    field_wrapper(method, options) do |opts|
      super(method, field_options(method, opts))
    end
  end

  def date_field(method, options = {})
    field_wrapper(method, options) do |opts|
      super(method, field_options(method, opts))
    end
  end

  def search_field(method, options = {})
    field_wrapper(method, options) do |opts|
      super(method, field_options(method, opts))
    end
  end

  def text_area(method, options = {})
    options[:rows] ||= 4
    field_wrapper(method, options) do |opts|
      super(method, field_options(method, opts))
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
      super(method, opts.merge(class: merge_classes(FILE_FIELD_CLASSES, opts[:class])))
    end
  end

  def submit(value = nil, options = {})
    super(value, options.merge(class: merge_classes(SUBMIT_CLASSES, options[:class])))
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

  def field_options(method, options)
    custom_class = options.delete(:class)
    base = "#{FIELD_BASE} #{has_errors?(method) ? FIELD_ERROR : FIELD_NORMAL}"
    options[:class] = merge_classes(base, custom_class)
    options[:id] ||= field_id(method)
    options.merge!(aria_attributes(method, options))
    options
  end

  def select_html_options(method, wrapper_opts)
    base = "#{FIELD_BASE} #{has_errors?(method) ? FIELD_ERROR : FIELD_NORMAL}"
    {
      class: base,
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

  def has_errors?(method)
    object&.errors&.[](method)&.any? || false
  end

  def field_id(method)
    "#{@object_name}_#{method}"
  end

  def merge_classes(*classes)
    classes.compact.join(" ").squish
  end
end
