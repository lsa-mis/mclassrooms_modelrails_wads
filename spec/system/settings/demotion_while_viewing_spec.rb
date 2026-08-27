require "rails_helper"

RSpec.describe "Settings hub — demotion while viewing", type: :system do
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Corp") }
  # Members moved off the settings layout into the workspace shell (nav IA
  # refactor Task 3); the equivalent of the old settings-hub <aside> for this
  # page is the shell's secondary sub-nav (_workspace_settings_subnav).
  let(:sidebar_selector) { "nav[aria-label='#{I18n.t("settings.sidebar.strip_heading.workspace")}']" }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    @member_ms = create(:membership, :admin, user: member, workspace: workspace)
    @viewer_role = Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" }
  end

  # The workspace shell layout subscribes to the workspace stream
  # (turbo_stream_from Current.workspace) and Membership broadcasts via
  # Broadcastable on update. When an admin in another tab demotes this user,
  # the broadcast fires a refresh that Turbo morphs into the open tab —
  # re-evaluating SettingsNavigationHelper#workspace_settings_nav_items's
  # Pundit gating against the new role. The Limits & Plan link is the cleanest
  # assertion target: it gates on Workspaces::SettingsPolicy#update?
  # (manage_settings), which Admin has and Viewer does not. Members link gates
  # on membership.present?, which doesn't flip across the demotion.
  it "re-renders the sidebar via Turbo morph when the user's role is changed in another tab" do
    sign_in_via_form(member)
    visit workspace_members_path(workspace)

    within(sidebar_selector) do
      expect(page).to have_link(I18n.t("settings.sidebar.items.limits_and_plan"))
    end

    # Simulate the "other tab" admin demoting this user. The after_update_commit
    # broadcast on Membership fires broadcast_refresh_to workspace, which the
    # current tab's turbo_stream_from picks up and morphs in.
    @member_ms.update!(role: @viewer_role)

    # Wait for the broadcast to LAND, not for a duration: the morph re-renders
    # this member's own role cell, so the new role name appearing there is the
    # observable that the whole round trip (commit → Solid Cable → WebSocket →
    # morph) completed. wait: 15 because a 5s budget lost to that trip under
    # the 18-worker pre-push suite (#841) — an absence assertion alone cannot
    # distinguish "morph pending" from "gating broken".
    within("##{ActionView::RecordIdentifier.dom_id(@member_ms, :role)}") do
      expect(page).to have_text(@viewer_role.name, wait: 15)
    end

    # Morph landed; the demoted link's absence needs no budget of its own.
    within(sidebar_selector) do
      expect(page).not_to have_link(I18n.t("settings.sidebar.items.limits_and_plan"))
    end
  end
end
