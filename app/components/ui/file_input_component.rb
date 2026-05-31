# frozen_string_literal: true

module UI
  class FileInputComponent < ApplicationComponent
    # Matches the host app's FILE_FIELD_CLASSES (state-independent). a11y params
    # added so the builder can wire aria-invalid/describedby — closing the gap
    # where the app's plain file_field skipped ARIA.
    BASE = "block w-full text-sm text-text-body " \
           "file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-medium " \
           "file:bg-interactive file:text-text-on-interactive hover:file:bg-interactive-hover " \
           "file:cursor-pointer file:min-h-[var(--form-input-height)]"

    # accept:   MIME types or extensions, e.g. "image/*" or ".pdf,.docx"
    # multiple: allow selecting multiple files
    # required/invalid/describedby: form + a11y wiring (see UI::InputComponent)
    def initialize(accept: nil, multiple: false, required: false, invalid: false, describedby: nil, **html_attrs)
      @accept = accept
      @multiple = multiple
      @required = required
      @invalid = invalid
      @describedby = describedby
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      attrs = { type: "file", class: cn(BASE, @extra_class) }
      attrs[:accept] = @accept if @accept
      attrs[:multiple] = true if @multiple
      if @required
        attrs[:required] = true
        attrs["aria-required"] = "true"
      end
      attrs["aria-invalid"] = "true" if @invalid
      attrs["aria-describedby"] = @describedby if @describedby.present?
      content_tag(:input, nil, **attrs, **@html_attrs)
    end
  end
end
