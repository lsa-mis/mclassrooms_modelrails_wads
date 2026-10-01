# frozen_string_literal: true

require "rails_helper"

# Guards that each settings controller declares an explicit context (:identity or
# :workspace) and that the layout renders the matching sidebar partial — not a
# personal?/org? branch. (WorkspacesController#edit — personal or org — moved
# off this layout entirely in the nav IA refactor Task 2, and
# Workspaces::MembersController/InvitationsController followed in Task 3; see
# the dedicated describe blocks below and
# spec/requests/workspaces/profile_in_shell_spec.rb +
# spec/requests/workspaces/members_in_shell_spec.rb.)
#
# Uses Capybara.string (no browser) to parse real rendered HTML.
RSpec.describe "Settings sidebar context routing", type: :request do
  include_context "settings sidebar items"

  let(:user) { create(:user) }

  def sidebar(body)
    Capybara.string(body)
            .find("aside[aria-label='#{I18n.t("settings.sidebar.aria_label")}']")
  end

  before { sign_in(user) }

  # ── Identity context ────────────────────────────────────────────────────────

  describe "GET /settings/profile/edit (identity context)" do
    before { get edit_settings_profile_path }

    # The identity/workspace `data-workspace-kind` split lived on the settings
    # layout when it served both contexts. It's gone now that the layout is
    # account-only (nav IA refactor Task 5) — see
    # spec/requests/settings/account_only_layout_spec.rb, which asserts its
    # absence.

    it "renders identity sidebar items (Notifications, Security, Appearance)" do
      sb = sidebar(response.body)
      expect(sb).to have_link(item("notifications"))
      expect(sb).to have_link(item("security"))
      expect(sb).to have_link(item("appearance"))
    end

    it "does not render workspace sidebar items in identity context" do
      sb = sidebar(response.body)
      expect(sb).to have_no_link(item("members"))
      expect(sb).to have_no_link(item("invitations"))
    end
  end

  # ── Workspace context ───────────────────────────────────────────────────────
  # Members/Invitations moved off the settings layout into the workspace shell
  # (nav IA refactor Task 3) — the "sidebar" here is the shell's secondary
  # sub-nav (_workspace_settings_subnav), not the settings-hub <aside>.

  def workspace_subnav(body)
    Capybara.string(body)
            .find("nav[aria-label='#{I18n.t("settings.sidebar.strip_heading.workspace")}']")
  end

  describe "GET /workspaces/:slug/members (workspace shell)" do
    let!(:workspace) { create(:workspace) }
    before do
      create(:membership, :owner, user: user, workspace: workspace)
      get workspace_members_path(workspace)
    end

    it "renders in the workspace shell, not the settings hub" do
      expect(Capybara.string(response.body)).to have_no_css("[data-workspace-kind='workspace']")
      expect(Capybara.string(response.body)).to have_no_css("#settings-aria-live")
    end

    it "renders workspace sub-nav items (Members present)" do
      expect(workspace_subnav(response.body)).to have_link(item("members"))
    end

    it "does not render identity sidebar items in the workspace sub-nav" do
      sb = workspace_subnav(response.body)
      expect(sb).to have_no_link(item("notifications"))
      expect(sb).to have_no_link(item("security"))
      expect(sb).to have_no_link(item("appearance"))
    end
  end

  # ── Personal workspace edit → workspace shell, not identity settings ──────

  describe "GET /workspaces/:slug/edit for a personal workspace" do
    # The personal workspace is the workspace created automatically for the
    # user. WorkspacesController#edit now renders in the workspace shell
    # (layouts/application.html.erb) for every workspace — personal or org —
    # since it moved off the settings layout (nav IA refactor Task 2). The
    # old identity/workspace `data-workspace-kind` split only exists on the
    # settings layout and no longer applies to this action; shell rendering
    # itself is covered by spec/requests/workspaces/profile_in_shell_spec.rb.
    # This guards the one thing specific to *personal* workspaces: no
    # identity-settings items leak in via workspace_settings_nav_items.
    let(:personal_workspace) { user.personal_workspace }

    before do
      # WorkspacesController#edit authorizes via WorkspacePolicy — the user is
      # owner of their personal workspace, so this is permitted.
      get edit_workspace_path(personal_workspace)
    end

    it "renders in the workspace shell, not the settings hub" do
      expect(Capybara.string(response.body)).to have_no_css("[data-workspace-kind='identity']")
      expect(Capybara.string(response.body)).to have_no_css("#settings-aria-live")
    end

    it "does not show identity sidebar items in the workspace nav (Notifications/Security/Appearance absent)" do
      # Scoped to the workspace primary <aside> — the page body also contains
      # a "Notifications" link in the global header's user menu, which is
      # unrelated to settings-context routing.
      workspace_nav = Capybara.string(response.body)
                        .find("aside[aria-label='#{I18n.t("workspaces.sidebar.aria_label")}']")
      expect(workspace_nav).to have_no_link(item("notifications"))
      expect(workspace_nav).to have_no_link(item("security"))
      expect(workspace_nav).to have_no_link(item("appearance"))
    end
  end
end
