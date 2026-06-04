# frozen_string_literal: true

module UI
  # # Separator
  #
  # A thin rule that divides content along the horizontal or vertical axis. It is
  # decorative by default (`role="none"`); mark it semantic when the divide conveys
  # real grouping that assistive tech must perceive.
  #
  # ## Use when
  # - You need a visual rule between sections, list items, or toolbar groups.
  # - The divide carries meaning (a real boundary between groups) — pass
  #   `decorative: false` so the separator is announced.
  #
  # ## Don't use when
  # - The boundary is purely cosmetic *and* already implied by layout — a decorative
  #   separator is fine, but don't leave a meaningful grouping divide as decorative
  #   (AT users then lose the boundary).
  #
  # ## Accessibility contract
  # - **Guarantees:** `aria-orientation` is emitted ONLY on a semantic separator
  #   (`role="separator"`); it is omitted on a decorative one (`role="none"`), where
  #   `aria-orientation` is invalid.
  # - **You supply:** `decorative: false` when the divide conveys grouping; otherwise
  #   the default decorative treatment is correct.
  class SeparatorComponent < ApplicationComponent
    ORIENTATIONS = {
      horizontal: "bg-border h-px w-full shrink-0",
      vertical: "bg-border h-full w-px shrink-0"
    }.freeze

    def initialize(orientation: :horizontal, decorative: true, **html_attrs)
      @orientation = orientation.to_sym
      @decorative = decorative
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      attrs = {
        role: (@decorative ? "none" : "separator"),
        class: cn(ORIENTATIONS[@orientation], @extra_class)
      }
      # aria-orientation is invalid on role="none" — emit it only when the
      # separator is semantic (role="separator").
      attrs[:"aria-orientation"] = @orientation.to_s unless @decorative

      content_tag(:div, nil, **attrs, **@html_attrs)
    end
  end
end
