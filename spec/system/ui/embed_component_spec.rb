# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the embed component.
#
# Every embed renders a non-blank iframe `title` (the accessible name of the
# embedded region). We prove the titled iframe is present per provider and that
# the wrapper clears AAA in both themes. The per-spec axe call runs the default
# (AA) rule set; the authoritative AAA 7:1 audit is the CI-only wcag2aaa
# after-hook (spec/support/axe_accessibility.rb).
RSpec.describe "Embed component accessibility", type: :system do
  let(:scope) { [ "[data-test='embed']" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  it "youtube: a titled iframe is present; AAA in both themes" do
    visit "/rails/view_components/ui/embed_component/youtube"

    expect(page).to have_css("iframe[title]", visible: :all)
    expect_aaa_in_both_themes
  end

  it "map: a titled iframe is present; AAA in both themes" do
    visit "/rails/view_components/ui/embed_component/map"

    expect(page).to have_css("iframe[title]", visible: :all)
    expect_aaa_in_both_themes
  end
end
