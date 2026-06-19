# frozen_string_literal: true

require "rails_helper"

# Guards that each settings controller declares an explicit context (:identity or
# :workspace) and that the layout renders the matching sidebar partial — not a
# personal?/org? branch. The hard goal (Task 3): visiting edit_workspace_path
# for a *personal* workspace must render the workspace sidebar, proving that the
# old personal?→identity conflation is dead.
#
# Uses Capybara.string (no browser) to parse real rendered HTML.
RSpec.describe "Settings sidebar context routing", type: :request do
  let(:user) { create(:user) }

  def sidebar(body)
    Capybara.string(body)
            .find("aside[aria-label='#{I18n.t("settings.sidebar.aria_label")}']")
  end

  def item(key)
    I18n.t("settings.sidebar.items.#{key}")
  end

  before { sign_in(user) }

  # ── Identity context ────────────────────────────────────────────────────────

  describe "GET /settings/profile/edit (identity context)" do
    before { get edit_settings_profile_path }

    it "renders data-workspace-kind='identity'" do
      expect(Capybara.string(response.body)).to have_css("[data-workspace-kind='identity']")
    end

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

  describe "GET /workspaces/:slug/members (workspace context)" do
    let!(:workspace) { create(:workspace) }
    before do
      create(:membership, :owner, user: user, workspace: workspace)
      get workspace_members_path(workspace)
    end

    it "renders data-workspace-kind='workspace'" do
      expect(Capybara.string(response.body)).to have_css("[data-workspace-kind='workspace']")
    end

    it "renders workspace sidebar items (Members present)" do
      expect(sidebar(response.body)).to have_link(item("members"))
    end

    it "does not render identity sidebar items in workspace context" do
      sb = sidebar(response.body)
      expect(sb).to have_no_link(item("notifications"))
      expect(sb).to have_no_link(item("security"))
      expect(sb).to have_no_link(item("appearance"))
    end
  end

  # ── Hard goal: personal workspace → workspace context (Task 3) ────────────

  describe "GET /workspaces/:slug/edit for a personal workspace (workspace context)" do
    # The personal workspace is the workspace created automatically for the user.
    # WorkspacesController declares settings_context :workspace, so even though
    # the workspace is personal? == true, the workspace sidebar must render.
    let(:personal_workspace) { user.personal_workspace }

    before do
      # WorkspacesController#edit authorizes via WorkspacePolicy — the user is
      # owner of their personal workspace, so this is permitted.
      get edit_workspace_path(personal_workspace)
    end

    it "renders data-workspace-kind='workspace' (not 'identity')" do
      expect(Capybara.string(response.body)).to have_css("[data-workspace-kind='workspace']")
    end

    it "does NOT render data-workspace-kind='identity' for a personal workspace" do
      expect(Capybara.string(response.body)).to have_no_css("[data-workspace-kind='identity']")
    end

    it "does not show identity sidebar items (Notifications/Security/Appearance absent)" do
      sb = sidebar(response.body)
      expect(sb).to have_no_link(item("notifications"))
      expect(sb).to have_no_link(item("security"))
      expect(sb).to have_no_link(item("appearance"))
    end
  end
end
