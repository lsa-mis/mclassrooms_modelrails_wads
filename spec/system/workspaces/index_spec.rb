require "rails_helper"

RSpec.describe "Strong workspaces index", type: :system, js: true do
  let(:user) { create(:user, first_name: "Dave", last_name: "Hancock") }
  let(:current_workspace) { create(:workspace, name: "Recent") }
  let(:older_workspace) { create(:workspace, name: "Older") }

  let!(:current_membership) {
    create(:membership, :owner, user: user, workspace: current_workspace,
                                last_accessed_at: 2.minutes.ago)
  }
  let!(:older_membership) {
    create(:membership, user: user, workspace: older_workspace,
                        last_accessed_at: 3.days.ago)
  }
  # Seed a co-owner for current_workspace so user can leave it in later examples.
  let!(:co_owner) {
    other = create(:user)
    create(:membership, :owner, user: other, workspace: current_workspace)
  }

  before { sign_in_via_form(user) }

  describe "page structure" do
    it "renders the page title and the New workspace CTA" do
      visit workspaces_path
      expect(page).to have_selector("h1", text: I18n.t("workspaces.index.title"))
      expect(page).to have_link(I18n.t("workspaces.index.new_workspace"))
    end

    it "pins the most-recently-accessed workspace at the top with a CURRENT badge" do
      visit workspaces_path
      pinned = page.find("[data-test='current-workspace-row']")
      within(pinned) do
        expect(page).to have_text("Recent")
        # Badge uses `uppercase` CSS class — match case-insensitively against the I18n value.
        expect(page).to have_text(/#{Regexp.escape(I18n.t('workspaces.index.current_badge'))}/i)
      end
    end

    it "renders an 'Other workspaces' heading and the older workspace below" do
      visit workspaces_path
      # Heading uses `uppercase` CSS class — match case-insensitively against the I18n value.
      expect(page).to have_text(/#{Regexp.escape(I18n.t('workspaces.index.other_workspaces_heading'))}/i)
      others_section = page.find("[data-test='other-workspaces-list']")
      within(others_section) do
        expect(page).to have_text("Older")
      end
    end
  end

  describe "row metadata" do
    it "shows plan, role, member count, and last-accessed text per row" do
      visit workspaces_path

      pinned = page.find("[data-test='current-workspace-row']")
      within(pinned) do
        expect(page).to have_text(I18n.t("workspaces.plans.free"))
        expect(page).to have_text(I18n.t("workspaces.index.row.role.owner"))
        expect(page).to have_text(I18n.t("workspaces.index.row.member", count: 2))
        # "Last accessed 2 minutes ago" — use a partial substring to avoid
        # locale/clock fragility.
        expect(page).to have_text(/Last accessed/)
      end

      others = page.find("[data-test='other-workspaces-list']")
      within(others) do
        expect(page).to have_text(I18n.t("workspaces.index.row.role.member"))
      end
    end

    it "shows 'Never accessed' for memberships with nil last_accessed_at" do
      never_workspace = create(:workspace, name: "Never visited")
      create(:membership, user: user, workspace: never_workspace, last_accessed_at: nil)
      visit workspaces_path
      expect(page).to have_text(I18n.t("workspaces.index.row.last_accessed.never"))
    end
  end

  describe "Switch action" do
    it "navigates to the workspace overview when the row is clicked" do
      visit workspaces_path
      within(page.find("[data-test='other-workspaces-list']")) do
        click_link "Older"
      end
      expect(page).to have_current_path(workspace_path(older_workspace))
    end

    it "renders a Switch button on every row (including the pinned current)" do
      visit workspaces_path
      pinned = page.find("[data-test='current-workspace-row']")
      within(pinned) do
        expect(page).to have_link(I18n.t("workspaces.index.row.switch"))
      end
      others = page.find("[data-test='other-workspaces-list']")
      within(others) do
        expect(page).to have_link(I18n.t("workspaces.index.row.switch"))
      end
    end
  end

  describe "Leave action" do
    it "does NOT render a Leave button on the pinned current row" do
      visit workspaces_path
      pinned = page.find("[data-test='current-workspace-row']")
      within(pinned) do
        expect(page).to have_no_button(I18n.t("workspaces.index.row.leave"))
      end
    end

    it "renders Leave on non-current rows where policy permits" do
      visit workspaces_path
      others = page.find("[data-test='other-workspaces-list']")
      within(others) do
        expect(page).to have_button(I18n.t("workspaces.index.row.leave"))
      end
    end

    it "does NOT render Leave on the personal workspace" do
      personal = create(:workspace, name: "Personal")
      create(:membership, :owner, user: user, workspace: personal, last_accessed_at: 1.year.ago)
      user.update!(personal_workspace_id: personal.id)
      visit workspaces_path

      # Find the row for Personal in either pinned or others.
      personal_row = page.all("li, [data-test='current-workspace-row']")
                          .find { |el| el.text.include?("Personal") }
      within(personal_row) do
        expect(page).to have_no_button(I18n.t("workspaces.index.row.leave"))
      end
    end

    it "removes the row after a successful leave" do
      visit workspaces_path
      others = page.find("[data-test='other-workspaces-list']")

      # Click Leave on the Older workspace. Confirm pattern uses turbo confirm.
      within(others) do
        accept_confirm do
          click_button I18n.t("workspaces.index.row.leave")
        end
      end

      expect(page).to have_current_path(workspaces_path)
      expect(page).to have_text(I18n.t("workspaces.members.destroy.left", workspace: "Older"))
      # Scope the row-removal assertion to the page's workspace listing region —
      # the flash banner above includes "You left Older.", which a global
      # have_no_text("Older") would incorrectly match.
      within("main") do
        expect(page).to have_no_selector("[data-test='other-workspaces-list']", text: "Older")
      end
    end
  end

  describe "single-membership user" do
    it "does NOT render the 'Other workspaces' heading when only one membership exists" do
      single_user = create(:user)
      only_workspace = create(:workspace, name: "Only One")
      create(:membership, :owner, user: single_user, workspace: only_workspace, last_accessed_at: 1.minute.ago)

      # Sign out the existing user, then sign in as single_user.
      # If there's no project sign_out helper, just visit destroy session path
      # or restart by visiting new_session_path and re-authenticating.
      cdp_clear_cookies
      sign_in_via_form(single_user)
      visit workspaces_path

      expect(page).to have_text("Only One")
      expect(page).to have_no_text(I18n.t("workspaces.index.other_workspaces_heading"))
    end
  end

  describe "sort order" do
    it "places never-visited workspaces alphabetically after touched ones" do
      a_never = create(:workspace, name: "AAA Never")
      z_never = create(:workspace, name: "ZZZ Never")
      create(:membership, user: user, workspace: a_never, last_accessed_at: nil)
      create(:membership, user: user, workspace: z_never, last_accessed_at: nil)
      visit workspaces_path

      # Order in 'Other workspaces': Older (touched 3d ago), AAA Never, ZZZ Never
      others = page.find("[data-test='other-workspaces-list']")
      names = others.all("li").map(&:text)
      expect(names.find_index { |t| t.include?("Older") }).to be < names.find_index { |t| t.include?("AAA Never") }
      expect(names.find_index { |t| t.include?("AAA Never") }).to be < names.find_index { |t| t.include?("ZZZ Never") }
    end
  end

  describe "accessibility (WCAG 2.2 AAA)" do
    let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

    it "passes axe at default viewport in both themes" do
      visit workspaces_path
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations: #{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    it "passes axe at iPhone-SE viewport in both themes (responsive sanity)" do
      cdp_resize(375, 667)
      visit workspaces_path
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations (375x667): #{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end
end
