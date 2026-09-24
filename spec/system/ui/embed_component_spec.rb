# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the embed component.
#
# Every embed renders a non-blank iframe `title` (the accessible name of the
# embedded region). We prove the titled iframe is present per provider and that
# the wrapper clears AAA in both themes. The per-spec axe call runs the default
# (AA) rule set; the authoritative AAA 7:1 audit is the CI-only wcag2aaa
# after-hook (spec/support/axe_accessibility.rb).
# The two previews here are the only ones left that reach a third party:
# `EmbedComponent` turns a caller's `url:`/`query:` into an iframe `src`, so a
# YouTube watch URL and a Maps query are the SUBJECT being demonstrated, not an
# arbitrary fixture. The `data:` swap that fixed the other six previews (#1207)
# would leave these demonstrating nothing.
#
# So the fetch is stopped at the BROWSER instead — spec/support/capybara.rb
# resolves those hosts to nothing for every system spec. That removes the
# suite's dependency on youtube.com and google.com (cost 1 and 2 of #1207)
# while leaving the preview itself intact for anyone browsing Lookbook in
# development, where a real embed is the point (#1233).
RSpec.describe "Embed component accessibility", type: :system do
  let(:scope) { [ "[data-test='embed']" ] }

  def expect_aaa_in_both_themes
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end

  # `visible: :all` was load-bearing by accident: it matched an iframe that had
  # not laid out, which is the only reason these did not fail when the network
  # went down. With the fetch blocked the wrapper still sizes itself (it carries
  # the aspect ratio), so the ordinary visible matcher holds — and the derived
  # src is asserted, which is the transformation the preview exists to show.
  it "youtube: a titled iframe carrying the derived embed URL; AAA in both themes" do
    visit "/rails/view_components/ui/embed_component/youtube"

    frame = page.find("[data-test='embed'] iframe")
    expect(frame[:title]).to be_present
    expect(frame[:src]).to include("youtube.com/embed/dQw4w9WgXcQ")
    expect_aaa_in_both_themes
  end

  it "map: a titled iframe carrying the derived embed URL; AAA in both themes" do
    visit "/rails/view_components/ui/embed_component/map"

    frame = page.find("[data-test='embed'] iframe")
    expect(frame[:title]).to be_present
    expect(frame[:src]).to include("Eiffel")
    expect_aaa_in_both_themes
  end
end
