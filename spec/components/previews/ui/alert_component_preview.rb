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
  # - **Guarantees:** an urgency-matched live region, AAA-contrast text, and a
  #   tone-matched severity icon (`aria-hidden` — a non-color severity cue;
  #   `icon: false` suppresses it).
  # - **You supply:** a title and/or description, and a valid `variant`.
  #
  # ## Variants
  # `default` · `info` · `success` · `warning` · `danger`
  # (`destructive` is a non-breaking alias for `danger`.)
  # @logical_path Feedback & Status
  class AlertComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Overview

    # Every AAA-proven tone on one screen.
    def showcase
    end

    # @!endgroup

    # @!group Examples

    # Neutral, informational message — announced politely (role=status).
    def default
    end

    # Informational signal on the info-tinted surface — announced politely (role=status).
    def info
    end

    # Success / confirmation on the success-tinted surface — announced politely (role=status).
    def success
    end

    # Warning on the warning-tinted surface — announced politely (role=status).
    def warning
    end

    # Error / destructive message — announced assertively (role=alert).
    # `variant: :destructive` is a non-breaking alias for `:danger`.
    def destructive
    end

    # Rich content via slots — a destructive summary wrapping a list of errors.
    def with_slots
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — an empty alert
    #
    # An alert with no title and no description renders an empty live region —
    # screen-reader users hear nothing. Always pass a message.
    # @label Don't · empty alert
    def dont_empty
    end

    # @!endgroup
  end
end
