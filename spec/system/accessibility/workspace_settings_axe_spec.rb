# frozen_string_literal: true

require "rails_helper"

# Task 10 of the workspace-nav-IA refactor: proves the four reshaped
# workspace-settings surfaces (Profile, Members, Limits & Plan, Invite) are
# axe-clean in both themes on their new shell placement (secondary sub-nav,
# breadcrumb, identity-bar link, tightened spacing).
#
# Per-spec axe runs AA locally; the AAA 7:1 audit is the CI-only wcag2aaa hook
# (see spec/support/axe_accessibility.rb). Do not claim AAA from a
# local run — CI is the gate.
RSpec.describe "Workspace settings section — AAA", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme", max_members: 50) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in_via_form(user) }

  it "Profile settings page is axe-clean at AAA (both themes)" do
    visit edit_workspace_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on workspace profile: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "Members page is axe-clean at AAA (both themes)" do
    visit workspace_members_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on workspace members: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "Limits & Plan page is axe-clean at AAA (both themes)" do
    visit edit_workspace_settings_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on limits & plan: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "Invite screen is axe-clean at AAA (both themes)" do
    visit new_workspace_invitation_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on invite screen: #{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  describe "open-link join link (hashed at rest → show-once)" do
    before do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
      workspace.update!(join_policy: "open_link")
    end

    it "show-once reveal state is axe-clean at AAA (both themes)" do
      visit edit_workspace_settings_path(workspace)
      click_button I18n.t("workspaces.settings.join_policy.generate")
      expect(page).to have_text(I18n.t("workspaces.settings.join_policy.show_once_warning_lead"))
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations on join-link reveal: #{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    it "masked steady state is axe-clean at AAA (both themes)" do
      create(:workspace_join_link, workspace: workspace, created_by: user)
      visit edit_workspace_settings_path(workspace)
      expect(page).to have_text(I18n.t("workspaces.settings.join_policy.masked_help"))
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations on join-link masked state: #{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    # #952: expiry is conveyed in words inside <time datetime>, never by colour
    # alone, and the expiry paragraph is the aria-describedby target for both
    # the rotate button and the masked stub.
    it "shows the live link's expiry in a time[datetime], wired to the rotate button and masked stub, and is axe-clean at AAA (both themes)" do
      link = create(:workspace_join_link, workspace: workspace, created_by: user)
      visit edit_workspace_settings_path(workspace)

      expect(page).to have_css(
        "p#join_link_expiry time[datetime='#{link.reload.expires_at.iso8601}']",
        text: I18n.l(link.expires_at, format: :long)
      )
      expect(page).to have_css("div[aria-describedby='join_link_expiry']")
      expect(find_button(I18n.t("workspaces.settings.join_policy.rotate"))[:"aria-describedby"])
        .to eq("join_link_expiry")

      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations on join-link expiry: #{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    it "shows the expired message in words (no colour cue) for a lapsed link, and is axe-clean at AAA (both themes)" do
      create(:workspace_join_link, workspace: workspace, created_by: user)
      travel_to 8.days.from_now do
        visit edit_workspace_settings_path(workspace)

        expect(page).to have_css("#join_link_expiry", text: I18n.t("workspaces.settings.join_policy.expired"))
        expect(page).not_to have_css("#join_link_expiry time")

        expect(axe_clean_in_both_themes?(axe_options)).to be(true),
          "AAA violations on expired join-link: #{axe_violations_in_both_themes(axe_options).join("\n")}"
      end
    end
  end
end
