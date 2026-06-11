# frozen_string_literal: true

module UI
  # # Spinner
  #
  # An animated busy indicator for indeterminate waits. Carries `role="status"` and
  # an sr-only loading label so the spin is announced, not silent.
  #
  # ## Use when
  # - You need to signal an indeterminate wait (submitting, fetching). For known
  #   percentages, use `progress`.
  #
  # ## Don't use when
  # - You strip the sr-only text — the spin then conveys nothing to AT.
  #
  # ## Accessibility contract
  # - **Guarantees:** `role="status"` + sr-only i18n loading label.
  # - **You supply:** nothing; override copy via `modelrails_ui.spinner.loading`.
  # @logical_path Feedback & Status
  class SpinnerComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Default spinner.
    def default
    end

    # Three sizes in a row.
    def sizes
    end

    # Centered inside a bordered surface.
    def on_surface
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — spinner with no status text
    #
    # A hand-built spinner with no `role="status"` and no sr-only text is silent to
    # screen readers — they get no loading signal. Use the component, which supplies
    # both.
    # @label Don't · no status text
    def dont_no_status_text
    end

    # @!endgroup
  end
end
