# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the ChatBubbleComponent (display-2).
#
# chat_bubble is a roleless presentational `<div>` — its key a11y fix is that the
# speaker is NEVER conveyed by alignment or color alone: every bubble carries an
# sr-only "You said" / "They said" direction label (and a visible author when given).
# These specs assert that label on the REAL rendered preview (not the unit harness),
# then audit AAA contrast on the bubble subtree.
#
# Each preview wraps the bubble(s) in `#cb-scope` so axe audits the COMPONENT, not the
# host chrome (the minimal preview layout yields the bubble next to a dev theme
# toggle). No color-contrast exclude — a real contrast failure on the sent fill
# (`bg-interactive` / `text-text-on-interactive`) or received surface
# (`bg-surface-sunken` / `text-text-body`) would still fail this spec, proving both
# clear AAA 7:1.
RSpec.describe "ChatBubble component accessibility", type: :system do
  # `let`, not a top-level constant (a constant inside describe leaks to ::SCOPE and
  # collides across scoped 0b specs → axe scopes to the wrong selector).
  let(:scope) { [ "#cb-scope" ] }

  it "sent: announces the speaker via an sr-only direction label; AAA in both themes" do
    visit "/rails/view_components/ui/chat_bubble_component/sent"

    expect(page).to have_css("#cb-scope .sr-only", text: "said", visible: :all)
    expect_aaa_in_both_themes(include: scope)
  end

  it "received: announces the speaker via an sr-only direction label; AAA in both themes" do
    visit "/rails/view_components/ui/chat_bubble_component/received"

    expect(page).to have_css("#cb-scope .sr-only", text: "said", visible: :all)
    expect_aaa_in_both_themes(include: scope)
  end

  it "with_meta: shows author + timestamp and keeps the sr-only label; AAA in both themes" do
    visit "/rails/view_components/ui/chat_bubble_component/with_meta"

    expect(page).to have_css("#cb-scope .sr-only", text: "said", visible: :all)
    expect(page).to have_text("Ada Lovelace")
    expect(page).to have_text("10:32 AM")
    expect_aaa_in_both_themes(include: scope)
  end
end
