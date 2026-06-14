require "rails_helper"

# Renders the org-context settings sidebar through the real request stack and
# asserts each role sees the correct nav links. The members index uses
# layout "settings" and is reachable by every role (MembershipPolicy#index? is
# just membership.present?), so the sidebar renders here even for lower roles —
# unlike edit_workspace_path, which redirects them before any sidebar shows.
#
# This is the fast, no-browser complement to
# spec/system/settings/org_context_spec.rb (which covers the Owner render, AAA,
# and the Viewer security redirect). It locks in the role matrix — in particular
# the Member "Profile + Limits & Plan hidden" path the system specs never reach. #151
RSpec.describe "Settings sidebar visibility (org context)", type: :request do
  let(:workspace) { create(:workspace, name: "Acme Corp") }

  def org_sidebar
    Capybara.string(response.body)
            .find("aside[aria-label='#{I18n.t("settings.sidebar.aria_label")}']")
  end

  def item(key)
    I18n.t("settings.sidebar.items.#{key}")
  end

  def sign_in_and_load(*traits)
    user = create(:user)
    create(:membership, *traits, user: user, workspace: workspace)
    sign_in(user)
    get workspace_members_path(workspace)
  end

  context "as an Owner" do
    before { sign_in_and_load(:owner) }

    it "shows all four org items" do
      expect(org_sidebar).to have_link(item("profile"))
      expect(org_sidebar).to have_link(item("members"))
      expect(org_sidebar).to have_link(item("invitations"))
      expect(org_sidebar).to have_link(item("limits_and_plan"))
    end
  end

  # The Profile + Limits & Plan gates consult Workspaces::ProfilePolicy /
  # Workspaces::SettingsPolicy (manage_settings), not the default WorkspacePolicy
  # (manage_workspace) — so an Admin, who lacks manage_workspace, still sees them.
  context "as an Admin (manage_settings without manage_workspace)" do
    before { sign_in_and_load(:admin) }

    it "shows all four org items" do
      expect(org_sidebar).to have_link(item("profile"))
      expect(org_sidebar).to have_link(item("members"))
      expect(org_sidebar).to have_link(item("invitations"))
      expect(org_sidebar).to have_link(item("limits_and_plan"))
    end
  end

  context "as a Member (no manage_settings)" do
    before { sign_in_and_load }

    it "shows the items gated only on membership" do
      expect(org_sidebar).to have_link(item("members"))
      expect(org_sidebar).to have_link(item("invitations"))
    end

    it "hides the manage_settings-gated items" do
      expect(org_sidebar).to have_no_link(item("profile"))
      expect(org_sidebar).to have_no_link(item("limits_and_plan"))
    end
  end

  it "never renders personal-context items in the org sidebar" do
    sign_in_and_load(:owner)

    expect(org_sidebar).to have_no_link(item("notifications"))
    expect(org_sidebar).to have_no_link(item("security"))
    expect(org_sidebar).to have_no_link(item("appearance"))
  end
end
