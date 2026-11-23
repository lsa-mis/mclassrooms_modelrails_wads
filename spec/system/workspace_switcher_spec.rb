# frozen_string_literal: true

require "rails_helper"

# System spec for the workspace switcher, which heads the workspace sidebar.
#
# It therefore only exists on workspace pages — the sidebar is the switcher's
# home, so this visits one rather than the workspaces index. The sidebar is
# `hidden md:flex`; the default viewport satisfies that, no resize needed.
RSpec.describe "Workspace switcher (sidebar)", type: :system do
  # Starts on the personal workspace so selecting the second one is a real navigation.
  def open_personal_workspace_of_two_workspace_user
    second = create(:workspace)
    user = create(:user)
    add_member(second, role: :owner, user: user)
    sign_in_via_form(user)
    visit workspace_path(user.personal_workspace)
    second
  end

  it "opens on click, lists both workspaces, and navigates on selection" do
    second = open_personal_workspace_of_two_workspace_user
    button = find("#workspace-switcher-button")
    expect(button["aria-expanded"]).to eq("false")

    button.click
    expect(button["aria-expanded"]).to eq("true")

    within "#workspace-switcher-menu" do
      expect(page).to have_link(second.name)
      click_link second.name
    end

    expect(page).to have_current_path(workspace_path(second))
  end

  it "closes on Escape" do
    open_personal_workspace_of_two_workspace_user
    find("#workspace-switcher-button").click
    expect(find("#workspace-switcher-button")["aria-expanded"]).to eq("true")

    cdp_press("Escape")

    expect(find("#workspace-switcher-button")["aria-expanded"]).to eq("false")
    expect(page).to have_no_css("#workspace-switcher-menu", visible: :visible)
  end

  it "is accessible with the menu open (wcag2aaa-scoped, both themes)" do
    open_personal_workspace_of_two_workspace_user
    axe_options = { runOnly: { type: "tag", values: [ "wcag2aaa" ] } }
    find("#workspace-switcher-button").click
    expect(find("#workspace-switcher-button")["aria-expanded"]).to eq("true")

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
