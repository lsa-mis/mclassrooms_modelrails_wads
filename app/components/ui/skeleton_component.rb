# frozen_string_literal: true

module UI
  # # Skeleton
  #
  # A pulsing placeholder block that stands in for content while it loads. Purely
  # decorative — it is hidden from assistive tech so screen readers don't announce
  # a series of empty boxes.
  #
  # ## Use when
  # - You need a low-jank loading placeholder for text lines, avatars, or cards.
  #   Shape each skeleton with `class:` (e.g. `"h-4 w-48"`, `"size-10 rounded-full"`).
  #
  # ## Don't use when
  # - There's no surrounding loading signal for AT. A skeleton is `aria-hidden`, so
  #   the region it fills must carry its own `aria-busy`/live-region status or
  #   screen-reader users get no indication anything is loading.
  #
  # ## Accessibility contract
  # - **Guarantees:** `aria-hidden="true"` (no empty-box announcements) and
  #   `motion-reduce:animate-none` (the pulse is suppressed for reduced-motion users).
  # - **You supply:** an `aria-busy` / live region on the surrounding container so AT
  #   users know content is loading; the size/shape via `class:`.
  class SkeletonComponent < ApplicationComponent
    BASE = "bg-surface-sunken animate-pulse motion-reduce:animate-none rounded-md"

    def initialize(**html_attrs)
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, nil,
        class: cn(BASE, @extra_class),
        "aria-hidden": "true",
        **@html_attrs)
    end
  end
end
