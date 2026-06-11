# frozen_string_literal: true

module UI
  # # ChatBubble
  #
  # A single message bubble for a chat or comment transcript. Presentational — it
  # styles *one* message (sent vs received) with an optional author, timestamp, and
  # decorative avatar. It is not the transcript: wrap a sequence in your own log
  # container (that container, not the bubble, carries `role="log"`).
  #
  # ## Use when
  # - Rendering an individual message in a chat thread, comment list, or inbox.
  #
  # ## Don't use when
  # - Who-spoke is conveyed by alignment/color alone — pass `author:` (or rely on the
  #   sr-only direction label) so a screen-reader user knows the speaker.
  # - You need it interactive — it is a presentational `<div>`.
  #
  # ## Accessibility contract
  # - **Guarantees:** the speaker is always perceivable in text (visible `author:` or
  #   an sr-only "You said" / "They said" label), AAA bubble fills (`bg-interactive` +
  #   `text-text-on-interactive` sent; `bg-surface-sunken` + `text-text-body`
  #   received), an AAA `text-text-muted` timestamp, and a decorative `aria-hidden`
  #   avatar.
  # - **You supply:** the body via slot content; optionally `author:`, `timestamp:`,
  #   and an `avatar:` URL (received only).
  # @logical_path Data Display
  class ChatBubbleComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # An outgoing message — right-aligned interactive fill.
    def sent
    end

    # An incoming message (default) — left-aligned sunken surface.
    def received
    end

    # With a named author and timestamp shown in the meta line.
    def with_meta
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — speaker conveyed by color/alignment only
    #
    # Sighted users read the side and fill to tell who spoke, but with no `author:`
    # and the sr-only direction label stripped, a screen-reader user gets nothing.
    # Keep the direction label (or pass `author:`).
    # @label Don't · color-only author
    def dont_color_only_author
    end

    # @!endgroup
  end
end
