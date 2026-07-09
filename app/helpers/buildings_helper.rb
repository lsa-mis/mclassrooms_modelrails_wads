# MiClassrooms Phase 4 Task 8 (Brief §5.3): the admin building-show floors
# list — one row per floor (label, classroom count, plan-attached indicator)
# extracted out of the view so buildings/show.html.erb's `list_group_item`
# loop stays a plain `href:`/block call, mirroring rooms/floor_plan.html.erb's
# same-floor room rows.
module BuildingsHelper
  # A decorative dot (UI::IndicatorComponent) next to real, visible text —
  # the text is what conveys "plan attached" to assistive tech; the dot is
  # aria-hidden and adds nothing on its own (WCAG 1.4.1: never color-only).
  def floor_row_body(floor)
    safe_join([
      content_tag(:span, floor.label, class: "font-medium text-text-heading"),
      content_tag(:span, t("buildings.show.floor_classroom_count", count: floor.rooms.classroom.count),
        class: "text-text-muted"),
      floor_plan_status(floor)
    ].compact, " ")
  end

  private

  def floor_plan_status(floor)
    return content_tag(:span, t("buildings.show.no_plan"), class: "text-sm text-text-muted") unless floor.plan.attached?

    content_tag(:span, class: "inline-flex items-center gap-2") do
      concat ui(:indicator, variant: :success) { content_tag(:span, nil, class: "block size-2", "aria-hidden": "true") }
      concat content_tag(:span, t("buildings.show.plan_attached"), class: "text-sm text-text-body")
    end
  end
end
