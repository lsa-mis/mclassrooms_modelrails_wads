# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Me (identity home)", type: :system do
  let(:user) { create(:user) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  it "shows identity, the user's workspaces, and a settings link" do
    sign_in_via_form(user)
    visit me_path

    expect(page).to have_css("h1", text: user.full_name)
    expect(page).to have_link(I18n.t("me.show.edit_in_settings"), href: edit_settings_profile_path)
    expect(page).to have_css("#me-workspaces-title")
    expect(page).to have_link(user.workspaces.first.name)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
