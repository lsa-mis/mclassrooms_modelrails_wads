# frozen_string_literal: true

require "rails_helper"

# Posture must be :none for the real server thread, so we mutate the shared
# Rails.configuration value and restore it after each example.
# (RSpec mocks do not cross into the Capybara/Playwright server thread.)
RSpec.describe "Onboarding journey", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  around do |example|
    original = Rails.configuration.x.tenancy.onboarding
    Rails.configuration.x.tenancy.onboarding = :none
    example.run
    Rails.configuration.x.tenancy.onboarding = original
  end

  # The workspace-creation step calls Role.find_by!(slug: "owner", workspace_id: nil).
  # The team-step populates the role dropdown from effective_roles, which includes
  # the global "member" role (workspace_id: nil). Both must exist.
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name        = "Owner"
      r.permissions = { "manage_workspace" => true, "manage_members" => true,
                        "manage_projects" => true, "manage_settings" => true }
    end
  end

  let!(:member_role) do
    Role.find_or_create_by!(slug: "member", workspace_id: nil) do |r|
      r.name        = "Member"
      r.permissions = { "manage_projects" => true }
    end
  end

  # A user that has no workspaces yet (the :with_zero_workspaces trait suppresses
  # the auto-workspace callback fired after factory creation).
  let(:user) { create(:user, :with_zero_workspaces) }

  before { sign_in_via_form(user) }

  describe "happy path: workspace → project → invite → project home" do
    it "walks all three wizard steps and lands on the project home" do
      # OnboardingsController#show is the dispatcher: it resolves the current step
      # and redirects. A zero-workspace user lands on the workspace step.
      visit onboarding_path
      expect(page).to have_current_path(new_onboarding_workspace_path)

      # --- Step 1: Name your workspace ---
      expect(page).to have_text(I18n.t("onboarding.workspaces.new.title"))
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations on workspace step:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

      fill_in I18n.t("onboarding.workspaces.new.name_label"), with: "Acme Co"
      click_button I18n.t("onboarding.workspaces.new.submit")

      # --- Step 2: Create your first project ---
      expect(page).to have_current_path(new_onboarding_project_path)
      expect(page).to have_text(I18n.t("onboarding.projects.new.title"))
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations on project step:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

      fill_in I18n.t("onboarding.projects.new.name_label"), with: "Acme Website"
      click_button I18n.t("onboarding.projects.new.submit")

      # --- Step 3: Invite your team ---
      expect(page).to have_current_path(new_onboarding_team_path)
      expect(page).to have_text(I18n.t("onboarding.teams.new.title"))
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations on team-invite step:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

      fill_in I18n.t("onboarding.teams.new.emails_label"), with: "sam@example.com"
      click_button I18n.t("onboarding.teams.new.submit")

      # --- Landing: project home ---
      # Reload after have_current_path so the navigation (and the server-side
      # onboarded_at write) is guaranteed complete before we check DB state.
      workspace = user.reload.workspaces.kept.first
      project   = workspace.projects.kept.first
      expect(page).to have_current_path(workspace_project_path(workspace, project))
      expect(user.reload.onboarded?).to be(true)
    end
  end

  describe "skip path: workspace → project → skip invite → project home" do
    it "lands on project home without sending invitations" do
      visit onboarding_path

      fill_in I18n.t("onboarding.workspaces.new.name_label"), with: "Skip Co"
      click_button I18n.t("onboarding.workspaces.new.submit")

      fill_in I18n.t("onboarding.projects.new.name_label"), with: "Skip Project"
      click_button I18n.t("onboarding.projects.new.submit")

      # Skip the invite step entirely via the "Skip for now" button.
      expect(page).to have_current_path(new_onboarding_team_path)
      click_button I18n.t("onboarding.teams.new.skip")

      workspace = user.reload.workspaces.kept.first
      project   = workspace.projects.kept.first
      expect(page).to have_current_path(workspace_project_path(workspace, project))
      expect(user.reload.onboarded?).to be(true)
    end
  end
end
