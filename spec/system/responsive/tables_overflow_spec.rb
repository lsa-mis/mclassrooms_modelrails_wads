# frozen_string_literal: true

require "rails_helper"

# W1-1 (2026-08-22 view-layer audit (internal)): at tablet/phone widths the
# members table's trailing columns — including every row's action links —
# were clipped unreachable by an overflow-hidden wrapper. Tables now sit in
# a UI::ScrollArea region: horizontally scrollable, keyboard-focusable, and
# named — with pagination OUTSIDE the region so it stays put while the table
# scrolls. The project-memberships table carried the identical wrapper
# pattern and is covered here too (panel checkpoint 1).
#
# skip_axe_hook: axe runs INSIDE the viewport block instead — the suite-wide
# hook fires after the viewport restore and would audit the desktop layout
# (see spec/support/responsive_viewport.rb).
RSpec.describe "Tables at narrow viewports", type: :system, skip_axe_hook: true do
  let(:user) { create(:user, first_name: "Owner", last_name: "User") }

  before { sign_in_via_form(user) }

  def scroll_region(label)
    find("[role='region'][aria-label='#{label}']")
  end

  def expect_horizontally_scrollable(region)
    overflows = page.evaluate_script(
      "arguments[0].scrollWidth > arguments[0].clientWidth", region
    )
    expect(overflows).to be(true),
      "table content does not overflow its region at this width — " \
      "the scroll assertions below would prove nothing"

    # User-scrollable vs clipped IS a computed-style distinction: programmatic
    # scrolling works on overflow-hidden containers too, so geometry cannot
    # discriminate the defect. The lane's sanctioned computed-style case.
    overflow_x = page.evaluate_script("getComputedStyle(arguments[0]).overflowX", region)
    expect(overflow_x).to eq("auto")

    # Keyboard-operable per the ScrollArea contract: the region is a tab stop,
    # so keyboard-only users can arrow-scroll to columns with no focusables.
    expect(region[:tabindex]).to eq("0")
  end

  describe "workspace members table" do
    let(:workspace) { create(:workspace) }

    before do
      create(:membership, :owner, user: user, workspace: workspace)
      alice = create(:user, first_name: "Alice", last_name: "Anderson",
                            email_address: "alice.anderson@engineering.example.com")
      create(:membership, :admin, user: alice, workspace: workspace)
    end

    it "keeps row actions reachable at 768px via a scrollable, keyboard-focusable region" do
      with_viewport(ResponsiveViewport::TABLET) do
        visit workspace_members_path(workspace)

        region = scroll_region(I18n.t("workspaces.members.index.table_label"))
        expect_horizontally_scrollable(region)

        # A real last-column row action exists inside the region (tbody-scoped
        # so this cannot match a thead sort link).
        expect(region).to have_css("tbody td:last-child a, tbody td:last-child button",
                                   visible: :all)

        # The region wraps ONLY the table: pagination (or anything else) inside
        # it would scroll off-screen with the table. Structural, so it holds
        # whether or not this page has enough rows to render a pager.
        only_table = page.evaluate_script(
          "arguments[0].children.length === 1 && arguments[0].children[0].tagName === 'TABLE'",
          region
        )
        expect(only_table).to be(true),
          "scroll region must wrap only the table — anything else scrolls with it"

        expect(axe_violations_in_both_themes).to be_empty
      end
    end
  end

  describe "project memberships table" do
    let(:workspace) { user.workspaces.sole }
    let(:project)   { create(:project, workspace: workspace, created_by: user) }

    before do
      create(:project_membership, :creator, project: project, user: user)
      # A long member name forces the table past 375px so the overflow
      # precondition is deterministic rather than font-metrics luck.
      long_named = create(:user, first_name: "Bartholomew-Alexander",
                                 last_name: "Wolfeschlegelsteinhausen")
      create(:project_membership, project: project, user: long_named)
    end

    it "keeps the actions column reachable at 375px via a scrollable, keyboard-focusable region" do
      with_viewport(ResponsiveViewport::PHONE) do
        visit workspace_project_memberships_path(workspace, project)

        region = scroll_region(I18n.t("workspaces.projects.memberships.index.table_label"))
        expect_horizontally_scrollable(region)

        expect(region).to have_css("tbody td:last-child a, tbody td:last-child button",
                                   visible: :all)

        expect(axe_violations_in_both_themes).to be_empty
      end
    end
  end
end
