# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the footer component.
#
# footer renders a `<footer>` contentinfo landmark, so axe scopes by `footer` — the
# minimal preview layout emits no footer of its own, so this scopes cleanly to the
# component. NO color-contrast exclude: proves the AAA tokens on `bg-surface-raised`
# (incl. `text-text-muted`, which is the same neutral as body here) in both themes.
RSpec.describe "Footer component accessibility", type: :system do
  # `let`, not a top-level constant (a constant inside describe leaks to ::SCOPE and
  # collides across scoped 0b specs → axe scopes to the wrong selector).
  let(:scope) { [ "footer" ] }

  it "default: renders semantic link columns with focus-ring links; AAA in both themes" do
    visit "/rails/view_components/ui/footer_component/default"

    expect(page).to have_css("footer ul li a")
    expect(page).to have_css("footer a.focus-ring")
    expect_aaa_in_both_themes(include: scope)
  end

  it "minimal: copyright-only footer passes AAA in both themes" do
    visit "/rails/view_components/ui/footer_component/minimal"

    expect(page).to have_css("footer")
    expect_aaa_in_both_themes(include: scope)
  end
end
