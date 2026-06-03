# frozen_string_literal: true

module UI
  # # Alert
  #
  # An inline contextual message banner (NOT the flash/toast pipeline). Announced
  # politely (`role="status"`) when neutral, assertively (`role="alert"`) when
  # destructive.
  #
  # ## Use when
  # - An inline, in-page message tied to surrounding content (form error summary,
  #   destructive-action warning, empty-state notice).
  #
  # ## Don't use when
  # - It's an ephemeral flash — use the app's toast system (`shared/_toasts`).
  #
  # ## Accessibility contract
  # - **Guarantees:** an urgency-matched live region and AAA-contrast text.
  # - **You supply:** a title and/or description, and a valid `variant`.
  #
  # ## Variants
  # `default` · `destructive`
  class AlertComponentPreview < ViewComponent::Preview
    include UIHelper

    # Neutral, informational message — announced politely (role=status).
    def default
    end

    # Error / destructive message — announced assertively (role=alert).
    def destructive
    end

    # Rich content via slots — a destructive summary wrapping a list of errors.
    def with_slots
    end

    # ## Don't — an empty alert
    #
    # An alert with no title and no description renders an empty live region —
    # screen-reader users hear nothing. Always pass a message.
    # @label Don't · empty alert
    def dont_empty
    end
  end
end
