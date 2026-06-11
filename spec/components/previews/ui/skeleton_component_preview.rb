# frozen_string_literal: true

module UI
  # # Skeleton
  #
  # A pulsing placeholder block shown while content loads. Decorative and
  # `aria-hidden` — the surrounding region must carry the loading signal for AT.
  #
  # ## Use when
  # - You need a loading placeholder for text lines, avatars, or cards. Shape each
  #   with `class:` (`"h-4 w-48"`, `"size-10 rounded-full"`).
  #
  # ## Don't use when
  # - The region has no `aria-busy`/live status — SR users get no loading signal.
  #
  # ## Accessibility contract
  # - **Guarantees:** `aria-hidden="true"` and `motion-reduce:animate-none`.
  # - **You supply:** an `aria-busy`/live region on the container; size via `class:`.
  # @logical_path Feedback & Status
  class SkeletonComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # A single text-line placeholder.
    def default
    end

    # A small composed card of skeletons.
    def card
    end

    # A circular avatar placeholder.
    def circle
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — no surrounding busy/live region
    #
    # These skeletons are `aria-hidden`, and nothing around them announces a loading
    # state, so screen-reader users get no signal at all. Wrap them in a container
    # with `aria-busy="true"` (or a live-region status).
    # @label Don't · no busy region
    def dont_no_busy_region
    end

    # @!endgroup
  end
end
