# frozen_string_literal: true

require "rails_helper"

# Preview-host WCAG 2.2 AAA proof for the card component.
#
# Card is a roleless presentational container (a plain non-interactive `<div>`),
# so there is no live-region role to scope by. Each preview wraps the card in
# `#card-scope` so axe audits the COMPONENT subtree, not the host chrome (the
# minimal preview layout emits best-practice advisories like landmark-one-main
# that are not WCAG and not about the card).
#
# No color-contrast exclude — a real contrast failure on the card's text
# (title / description / body) would still fail this spec, proving the AAA
# `text-text-body` / `text-text-heading` / `text-text-muted` tokens on
# `bg-surface-raised` in BOTH themes.
RSpec.describe "Card component accessibility", type: :system do
  # `let`, NOT a top-level constant: a constant assigned inside an RSpec.describe
  # block leaks to ::SCOPE, so multiple scoped 0b specs would clobber each other and
  # axe would scope to the wrong selector ("No elements found for include").
  let(:scope) { [ "#card-scope" ] }

  it "default: renders the titled card body and passes AAA in both themes" do
    visit "/rails/view_components/ui/card_component/default"

    expect(page).to have_css("#card-scope h2", text: "Account settings")
    expect(page).to have_css("#card-scope p", text: "Manage your account preferences.")
    expect(page).to have_css("#card-scope", text: "Update your name, email, and notification choices.")
    expect_aaa_in_both_themes(include: scope)
  end

  it "with_footer: renders header, body, and footer actions and passes AAA in both themes" do
    visit "/rails/view_components/ui/card_component/with_footer"

    expect(page).to have_css("#card-scope h2", text: "Delete project")
    expect(page).to have_css("#card-scope p", text: "This permanently removes the project and its data.")
    expect(page).to have_css("#card-scope", text: "You can export your data before deleting.")
    expect(page).to have_button("Cancel")
    expect(page).to have_button("Delete")
    expect_aaa_in_both_themes(include: scope)
  end
end
