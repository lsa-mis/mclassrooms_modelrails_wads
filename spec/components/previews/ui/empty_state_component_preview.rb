# frozen_string_literal: true

module UI
  # # Empty state
  #
  # The placeholder shown where a list, table or panel would be if it had anything
  # in it — an optional icon, a title, an optional supporting line, and an optional
  # call to action.
  #
  # ## Use when
  # - A list, table or panel has no rows and the page would otherwise look broken.
  # - A search or filter returned nothing and the user needs to know why.
  #
  # ## Don't use when
  # - Something FAILED. An empty state says "there is nothing here"; an error says
  #   "something went wrong". Use `alert`, so the tone and the ARIA role match.
  # - The data is still LOADING. Use `skeleton` — an empty state shown mid-fetch
  #   tells the user the wrong thing.
  #
  # ## Accessibility contract
  # - **Guarantees:** AAA-contrast tokens throughout; the title is a `<p>`, never a
  #   heading, so the component cannot inject one at an arbitrary level into a
  #   page's outline; slot regions carry `data-slot`.
  # - **You supply:** a `title:` worth reading, `aria-hidden="true"` on a decorative
  #   icon, and a live region around it when the empty state appears in response to
  #   a user action — the component does not announce its own arrival.
  # @logical_path Feedback & Status
  class EmptyStateComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Title only — the smallest useful form.
    def default
    end

    # Icon, supporting line and a call to action.
    def with_action
    end

    # A filled card, for an empty state sitting among other cards.
    def outlined
    end

    # No chrome, for a no-results block inside a panel that already has its own.
    def plain
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — an error dressed as an empty state
    #
    # "Nothing here" and "something went wrong" are different messages with
    # different urgency, and a screen reader should hear the difference. An empty
    # state has no alert role; use `alert` when something failed.
    # @label Don't · error as empty state
    def dont_error_as_empty
    end

    # @!endgroup
  end
end
