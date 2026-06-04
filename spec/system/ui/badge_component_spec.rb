# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the badge component.
#
# The badge is the per-surface-AAA risk component: most variants carry their own
# text/fill pair, but `ghost` and `outline` derive their contrast from the
# SURROUNDING surface (no self fill). The preview host body is
# `bg-surface-raised text-text-body` (see app/views/layouts/component_preview.html.erb),
# which in DARK mode is the LIGHTEST dark surface (neutral-800) — the worst case for
# text-on-surface contrast. This spec audits every meaningful variant UNSCOPED on the
# badge subtree (no color-contrast exclude) so a real contrast failure on any variant —
# including the adaptive `destructive` (white -> text-on-interactive) and the
# context-dependent `ghost`/`outline` — would FAIL here, not be hidden.
#
# `destructive` is the headline fix: it uses `text-text-on-interactive` (a dark neutral
# in dark mode), not `text-white`, so it must clear AAA on the light-pink dark-mode
# `--color-danger` fill. `ghost`/`outline` are audited because the reviewer flagged them
# context-dependent; if either genuinely fails AAA on this host surface that is a real
# token/variant finding, not something to exclude.
#
# The preview host's minimal layout emits axe best-practice advisories
# (landmark-one-main, page-has-heading-one) that are NOT WCAG and NOT about the badge.
# We scope the audit to the badge subtree by element type so those host-chrome
# advisories stay out of scope WITHOUT excluding any rule.
RSpec.describe "Badge component accessibility", type: :system do
  BADGE_PREVIEW = "/rails/view_components/ui/badge_component"

  # variant scenario => the element the badge renders as on that preview.
  # `link_href` passes `href:` so the component renders an <a>; every other
  # variant renders a <span>.
  {
    "default"     => "span",
    "secondary"   => "span",
    "destructive" => "span",
    "outline"     => "span",
    "ghost"       => "span",
    "link"        => "span",
    "link_href"   => "a"
  }.each do |scenario, element|
    it "#{scenario} renders a <#{element}> and passes AAA in both themes" do
      visit "#{BADGE_PREVIEW}/#{scenario}"

      # The badge is the only element of its kind inside the preview body, but
      # scope the matcher to the rounded-full pill class to be precise.
      expect(page).to have_css("#{element}.rounded-full")

      # Scope to the badge subtree so host-chrome best-practice advisories are
      # out of scope. NO color-contrast exclude — a real contrast failure on the
      # badge (any variant, either theme) still fails this spec.
      scope = [ "#{element}.rounded-full" ]
      expect(axe_clean_in_both_themes?(include: scope)).to(
        be(true),
        axe_violations_in_both_themes(include: scope).join("\n")
      )
    end
  end
end
