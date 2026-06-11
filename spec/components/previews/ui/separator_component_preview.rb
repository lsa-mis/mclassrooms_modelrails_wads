# frozen_string_literal: true

module UI
  # # Separator
  #
  # A thin rule that divides content. Decorative by default (`role="none"`); mark it
  # `decorative: false` when the divide conveys real grouping AT must perceive.
  #
  # ## Use when
  # - You need a visual rule between sections, list items, or toolbar groups.
  # - The divide carries meaning — pass `decorative: false` so it is announced.
  #
  # ## Don't use when
  # - A meaningful grouping boundary is left decorative — screen-reader users then
  #   lose the boundary.
  #
  # ## Accessibility contract
  # - **Guarantees:** `aria-orientation` is emitted ONLY on a semantic separator;
  #   omitted on a decorative one (where it would be invalid).
  # - **You supply:** `decorative: false` when the divide conveys grouping.
  # @logical_path Layout
  class SeparatorComponentPreview < ViewComponent::Preview
    include UIHelper

    # @!group Examples

    # Horizontal, decorative (the default).
    def default
    end

    # Vertical rule between inline items.
    def vertical
    end

    # Semantic — announced to assistive tech as a real boundary.
    def semantic
    end

    # @!endgroup

    # @!group Reference

    # ## Don't — meaningful boundary left decorative
    #
    # This separator divides two distinct groups, but it's left `decorative: true`,
    # so screen-reader users get no boundary at all. Pass `decorative: false` when
    # the divide conveys grouping.
    # @label Don't · decorative when semantic
    def dont_decorative_when_semantic
    end

    # @!endgroup
  end
end
