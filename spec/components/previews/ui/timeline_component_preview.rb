# frozen_string_literal: true

module UI
  # # Timeline
  #
  # A vertical, chronological sequence of events — each with a marker dot, an
  # optional time, a title, and optional body. Rendered as a semantic ordered
  # list (`<ol>`/`<li>`) because the order is meaningful.
  #
  # ## Use when
  # - Showing an activity feed, audit trail, release history, or any dated
  #   sequence where the order carries meaning.
  #
  # ## Don't use when
  # - The order is arbitrary — use a `list_group`.
  # - You'd hand-build `<div>` steps with a drawn line; that loses the
  #   list/sequence semantics for assistive tech (see the Don't below).
  #
  # ## Accessibility contract
  # - **Guarantees:** a real `<ol>` of `<li>`; the connector line and marker dots
  #   are decorative (`aria-hidden`); event times are perceivable `<time>` text
  #   (with an optional machine-readable `datetime`); AAA-contrast tokens; an
  #   unknown item `variant` raises in development.
  # - **You supply:** each event's `title:` (and optional `date:`/`datetime:`,
  #   `description:`, block body, and dot `variant:`).
  # @logical_path Data Display
  class TimelineComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Three events with times, titles, and bodies — a plain <ol> of <li>.
    def default
    end

    # Per-event dot variants (semantic signal fills) marking status along the way.
    def variants
    end

    # Machine-readable times: `date:` is the human label, `datetime:` feeds the
    # `<time datetime>` attribute so the value is parseable by AT and tooling.
    def with_datetime
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — non-semantic <div> steps
    #
    # Building the sequence as <div>s with a hand-drawn line gives assistive tech
    # no list or ordering — it's just a stack of unrelated text. Use `ui :timeline`
    # so the events are a real `<ol>`/`<li>` and the order is announced.
    # @label Don't · div steps
    def dont_div_steps
    end

    # @!endgroup
  end
end
