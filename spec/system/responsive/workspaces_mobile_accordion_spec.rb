# frozen_string_literal: true

require "rails_helper"

# Mobile-viewport behavior for the workspace-scoped (application layout)
# header accordion (below md). The accordion holds only GLOBAL chrome now
# (workspace switcher, user menu, theme toggle); the workspace section sub-nav
# (Overview/Settings) lives in an in-page strip, not here. Mirrors the
# settings accordion spec.
RSpec.describe "Workspace pages — mobile accordion", type: :system, js: true do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, max_members: 50) }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    sign_in_via_form(user)
    cdp_resize(375, 667)
  end

  it "shows the hamburger and reveals global chrome on tap (not the section sub-nav)" do
    visit workspace_path(workspace)
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      expect(page).to have_link(I18n.t("navigation.all_workspaces"))    # global chrome
    end
  end

  it "auto-closes on link tap inside the panel" do
    visit workspace_path(workspace)
    click_button I18n.t("navigation.mobile_menu.open")
    within("[data-mobile-menu-target='menu']") do
      # A global-chrome link (the section sub-nav no longer lives in the panel).
      click_link I18n.t("navigation.all_workspaces")
    end
    expect(page).to have_current_path(workspaces_path)
    expect(page).to have_css("[data-mobile-menu-target='menu'].hidden", visible: :all)
  end

  # #1077: the sidebar that carries workspace identity is display:none below
  # md, so a phone showed the section tabs with nothing naming the workspace
  # unless the hamburger was opened. The switcher now renders a second time
  # above the tabs — with its own id suffix, because the sidebar copy is
  # hidden, not absent, and unsuffixed it would duplicate every id.
  it "names the workspace and the viewer's role above the section tabs, hamburger closed" do
    visit workspace_path(workspace)

    expect(page).to have_css("[data-mobile-menu-target=button][aria-expanded=false]")
    expect(page).to have_text(workspace.name)
    expect(page).to have_text("Owner")

    identity_then_tabs = page.evaluate_script(<<~JS)
      (() => {
        const identity = document.querySelector("#workspace-switcher-button-mobile");
        const tabs = document.querySelector("#section-nav-strip-heading");
        if (!identity || !tabs) return "missing";
        return identity.compareDocumentPosition(tabs) & Node.DOCUMENT_POSITION_FOLLOWING ? "identity-first" : "tabs-first";
      })()
    JS
    expect(identity_then_tabs).to eq("identity-first")

    dupes = page.evaluate_script(<<~JS)
      (() => { const ids = [...document.querySelectorAll("[id]")].map(e => e.id);
               return ids.filter((id, i) => ids.indexOf(id) !== i); })()
    JS
    expect(dupes).to be_empty, "duplicate ids at 375px: #{dupes.inspect}"
  end

  it "passes axe AAA both themes both states" do
    visit workspace_path(workspace)

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (collapsed):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("navigation.mobile_menu.open")
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations (expanded):\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end
end
