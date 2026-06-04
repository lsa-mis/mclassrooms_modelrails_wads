# frozen_string_literal: true

require "rails_helper"

# Preview-host accessibility proof for the figure component.
#
# A semantic <figure> wraps content with an optional <figcaption>; the caption is
# a supplement, not a substitute for an inner image's own alt. The caption uses
# text-text-muted, which in this token system is the SAME neutral as body text
# (AAA 7:1) — de-emphasis is by size/weight, not lightness. This spec asserts the
# figure/figcaption association and audits each scenario scoped to the <figure>
# subtree with NO color-contrast exclude. NOTE: the per-spec assertion below runs
# axe's default (AA) rule set; the authoritative AAA 7:1 audit is the wcag2aaa
# after-hook that fires under CI (see spec/support/playwright_accessibility.rb).
RSpec.describe "Figure component accessibility", type: :system do
  it "default renders a figcaption and passes AAA in both themes" do
    visit "/rails/view_components/ui/figure_component/default"

    expect(page).to have_css("figure figcaption.text-text-muted")

    audit_figure
  end

  it "no_caption renders a figure with no figcaption and passes AAA in both themes" do
    visit "/rails/view_components/ui/figure_component/no_caption"

    expect(page).to have_css("figure")
    expect(page).to have_no_css("figure figcaption")

    audit_figure
  end

  def audit_figure
    scope = [ "figure" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
