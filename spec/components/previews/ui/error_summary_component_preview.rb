# frozen_string_literal: true

module UI
  # # Error Summary
  #
  # The form-level error panel and the announcement mechanism for failed
  # submits: focusable, autofocused, items link to their fields.
  #
  # ## Related
  # `form_field` · `alert`
  # @logical_path Forms & Inputs
  class ErrorSummaryComponentPreview < ViewComponent::Preview
    include UIHelper

    # Two field errors, each linking to its control's id.
    def default
    end

    # An object-level (`:base`) error has no field to link to.
    def with_unlinked_item
    end
  end
end
