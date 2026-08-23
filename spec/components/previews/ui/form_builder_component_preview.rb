# frozen_string_literal: true

module UI
  # # Form Builder
  #
  # Model-backed fields through FormFieldComponent, wired to ActiveModel::Errors.
  # No native `required` — aria-required only, so server-rendered errors always
  # get their round trip (see the class header in app/form_builders/ui/form_builder.rb).
  #
  # ## Related
  # `form_field` · `error_summary` · `input` · `select` · `checkbox`
  # @logical_path Forms & Inputs
  class FormBuilderComponentPreview < ViewComponent::Preview
    include UIHelper

    # A PORO for the preview — any ActiveModel object works with the builder.
    class Article
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :title, :string
      attribute :body, :string
      attribute :terms, :boolean
    end

    # A complete small form: text field with hint, textarea, checkbox row, submit.
    def default
    end

    # The failed-submit state: focused error summary linking to each field,
    # error-first aria-describedby, plain-paragraph inline errors.
    def with_errors
    end
  end
end
