# frozen_string_literal: true

require "rails_helper"

# W1-2 (2026-08-22 view-layer audit (internal)): at phone widths the
# project-show nav row overflowed (scrollWidth 385 > clientWidth 375) because
# its links laid out in a single non-wrapping flex row. The nav must wrap.
#
# skip_axe_hook: axe runs INSIDE the viewport block instead — the suite-wide
# hook fires after the viewport restore and would audit the desktop layout
# (see spec/support/responsive_viewport.rb).
RSpec.describe "Project nav at narrow viewports", type: :system, skip_axe_hook: true do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }

  before do
    create(:project_membership, :creator, project: project, user: user)
    sign_in_via_form(user)
  end

  it "keeps all project nav links on-screen at 375px" do
    with_viewport(ResponsiveViewport::PHONE) do
      visit workspace_project_path(workspace, project)

      # Scope by the i18n'd aria-label (a hardcoded string pre-fix) — the page
      # renders several nav landmarks (tool tabs, breadcrumbs, ...). Assert the
      # nav's OWN geometry: a page-wide scrollWidth check can go red for any
      # unrelated element and green while this nav still overflows a container.
      nav = find("nav[aria-label='#{I18n.t('workspaces.projects.show.nav_label')}']")

      fits = page.evaluate_script(
        "arguments[0].scrollWidth <= arguments[0].clientWidth", nav
      )
      expect(fits).to be(true), "project nav overflows its container at 375px"

      within(nav) do
        expect(page).to have_link(I18n.t("workspaces.projects.show.members"))
      end

      expect(axe_violations_in_both_themes).to be_empty
    end
  end
end
