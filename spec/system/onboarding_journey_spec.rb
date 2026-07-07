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
  let!(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name        = "Owner"
      r.permissions = { "manage_workspace" => true, "manage_members" => true,
                        "manage_projects" => true, "manage_settings" => true }
    end
  end

  # A user that has no workspaces yet (the :with_zero_workspaces trait suppresses
  # the auto-workspace callback fired after factory creation).
  let(:user) { create(:user, :with_zero_workspaces) }

  before { sign_in_via_form(user) }

  describe "happy path: workspace → workspace home" do
    it "walks the single wizard step and lands on the workspace home" do
      # OnboardingsController#show is the dispatcher: it resolves the current step
      # and redirects. A zero-workspace user lands on the workspace step.
      visit onboarding_path
      expect(page).to have_current_path(new_onboarding_workspace_path)

      # --- Step: Name your workspace ---
      expect(page).to have_text(I18n.t("onboarding.workspaces.new.title"))
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations on workspace step:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

      fill_in I18n.t("onboarding.workspaces.new.name_label"), with: "Acme Co"
      click_button I18n.t("onboarding.workspaces.new.submit")

      # --- Landing: workspace home ---
      # Reload after have_current_path so the navigation (and the server-side
      # onboarded_at write) is guaranteed complete before we check DB state.
      workspace = user.reload.workspaces.kept.first
      expect(page).to have_current_path(workspace_path(workspace))
      expect(user.reload.onboarded?).to be(true)
    end
  end
end
