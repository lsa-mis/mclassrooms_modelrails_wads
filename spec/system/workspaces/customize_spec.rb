# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Personal workspace Customize", type: :system do
  # The Customize button on the personal-workspace Overview opens a modal
  # where the owner can rename the workspace (and change the logo). This
  # replaces the old "Settings" sidebar entry for personal workspaces
  # (workspace-settings IA Phase 1 Task 2).

  let(:user) { create(:user) }

  before { sign_in_via_form(user) }

  it "renames the workspace in-context from the Overview" do
    visit workspace_path(user.workspaces.kept.sole)

    click_on I18n.t("workspaces.overview.customize.open")
    fill_in I18n.t("workspaces.overview.customize.name_label"), with: "My Stuff"
    click_on I18n.t("workspaces.overview.customize.save")

    expect(page).to have_css("#workspace-name-heading", text: "My Stuff")
  end

  it "exposes the logo-picker trigger inside the Customize modal" do
    visit workspace_path(user.workspaces.kept.sole)

    click_on I18n.t("workspaces.overview.customize.open")

    expect(page).to have_css("dialog[open]")
    # The logo-trigger button (aria-label, no visible text) is inside the open dialog
    within("dialog[open]") do
      expect(page).to have_css("button[aria-label='#{I18n.t("workspaces.brandings.edit.change_logo")}']")
    end
  end

  it "clicking the logo trigger opens the identity-picker dialog" do
    # Verifies the dialog-inside-dialog stacking: the Customize <dialog> is open,
    # clicking the logo trigger opens a sibling identity-picker <dialog>, and
    # the hub turbo frame loads its source-selection radiogroup.
    visit workspace_path(user.workspaces.kept.sole)

    click_on I18n.t("workspaces.overview.customize.open")

    # Guard: confirm the Customize dialog opened and the trigger is present
    expect(page).to have_css("dialog#workspace-customize[open]")
    within("dialog#workspace-customize") do
      find("button[aria-label='#{I18n.t("workspaces.brandings.edit.change_logo")}']").click
    end

    # The identity-picker dialog is a sibling <dialog> that opens independently.
    # Wait for the hub turbo frame to load its source-selection radiogroup.
    expect(page).to have_css("#identity-picker-hub [role='radiogroup']", wait: 10)
    expect(page).to have_text(I18n.t("identity_picker.choose_workspace_logo"))
  end

  it "open Customize dialog passes AAA axe check in both themes" do
    # Scoped to the open Customize dialog element (#workspace-customize).
    # Locally axe runs AA only (wcag2aaa 7:1 hook is CI-only); a local pass
    # is necessary-not-sufficient — CI proves AAA.
    visit workspace_path(user.workspaces.kept.sole)

    click_on I18n.t("workspaces.overview.customize.open")

    # Guard: dialog must be open before we hand it to axe
    expect(page).to have_css("dialog#workspace-customize[open]")

    scope = [ "#workspace-customize" ]
    expect(axe_clean_in_both_themes?(include: scope)).to(
      be(true),
      axe_violations_in_both_themes(include: scope).join("\n")
    )
  end
end
