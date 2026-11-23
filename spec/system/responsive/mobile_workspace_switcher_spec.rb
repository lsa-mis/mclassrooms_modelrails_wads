# frozen_string_literal: true

require "rails_helper"

# System spec: the workspace switcher on a phone.
#
# The desktop switcher heads the sidebar, which is display:none below md. The
# same switcher renders a second time above the section tabs — with its own
# id suffix, because the sidebar copy is hidden, not absent, and unsuffixed it
# would duplicate every id (#1077). It replaced the inline list that used to
# live in the hamburger; the hamburger is global chrome only now.
RSpec.describe "Mobile workspace switcher — content column", type: :system, js: true do
  def create_owned_workspace(user)
    workspace = create(:workspace, max_members: 50)
    create(:membership, :owner, user: user, workspace: workspace)
    workspace
  end

  # Starts on the personal workspace so picking another one is a real navigation.
  def sign_in_on_phone(user)
    sign_in_via_form(user)
    cdp_resize(375, 667)
    user.reload
    visit workspace_path(user.personal_workspace)
  end

  it "is reachable without opening the hamburger, and lists both workspaces" do
    user = create(:user)
    second_workspace = create_owned_workspace(user)
    sign_in_on_phone(user)
    expect(page).to have_css("[data-mobile-menu-target=button][aria-expanded=false]")

    button = find("#workspace-switcher-button-mobile")
    expect(button["aria-expanded"]).to eq("false")
    button.click
    expect(button["aria-expanded"]).to eq("true")

    within("#workspace-switcher-menu-mobile") do
      expect(page).to have_link(user.personal_workspace.name, href: workspace_path(user.personal_workspace))
      expect(page).to have_link(second_workspace.name, href: workspace_path(second_workspace))
      expect(page).to have_link(I18n.t("navigation.all_workspaces"), href: workspaces_path)
    end
  end

  it "navigates to the selected workspace" do
    user = create(:user)
    second_workspace = create_owned_workspace(user)
    sign_in_on_phone(user)

    find("#workspace-switcher-button-mobile").click

    within("#workspace-switcher-menu-mobile") do
      click_link second_workspace.name
    end

    expect(page).to have_current_path(workspace_path(second_workspace))
  end

  # #1090: the index keeps the switcher in place too, in an "All workspaces"
  # state — the one authenticated page where the affordance used to vanish.
  describe "on the workspaces index" do
    it "shows the trigger in the All-workspaces state and navigates to a workspace from it" do
      user = create(:user)
      second_workspace = create_owned_workspace(user)
      sign_in_on_phone(user)
      visit workspaces_path

      trigger = find("#workspace-switcher-button-mobile")
      expect(trigger).to have_text(user.full_name)
      expect(trigger).to have_text(I18n.t("navigation.all_workspaces"))
      expect(trigger).to have_no_text("Owner")
      expect(page).to have_css("[data-test='workspaces-identity']", visible: :hidden)

      trigger.click
      within("#workspace-switcher-menu-mobile") do
        expect(page).to have_css("a[aria-current]", text: I18n.t("navigation.all_workspaces"))
        click_link second_workspace.name
      end

      expect(page).to have_current_path(workspace_path(second_workspace))
    end
  end

  # Placement in pixels, not class names, so the index and a workspace page
  # cannot drift apart — the index once floated 64px lower and 8px further in.
  it "sits on the content edge, the same distance under the header, on the index and a workspace page" do
    user = create(:user)
    second_workspace = create_owned_workspace(user)
    sign_in_on_phone(user)

    measure = lambda do |reference|
      page.evaluate_script(<<~JS)
        (() => {
          const rect = (s) => document.querySelector(s).getBoundingClientRect();
          return {
            gap: rect("#workspace-switcher-button-mobile").top - rect("header").bottom,
            avatar_left: rect("#workspace-switcher-button-mobile > span:first-child").left,
            reference_left: rect(#{reference.to_json}).left
          };
        })()
      JS
    end

    visit workspaces_path
    index = measure.call("main h1")
    visit workspace_path(second_workspace)
    workspace = measure.call("nav[aria-labelledby='section-nav-strip-heading'] a")

    expect(index["avatar_left"]).to eq(index["reference_left"])
    expect(workspace["avatar_left"]).to eq(workspace["reference_left"])
    expect(workspace["gap"]).to eq(index["gap"])
    expect(index["gap"]).to be_between(0, 32)
  end

  it "closes on Escape" do
    sign_in_on_phone(create(:user))

    find("#workspace-switcher-button-mobile").click
    expect(find("#workspace-switcher-button-mobile")["aria-expanded"]).to eq("true")

    cdp_press("Escape")

    expect(find("#workspace-switcher-button-mobile")["aria-expanded"]).to eq("false")
    expect(page).to have_no_css("#workspace-switcher-menu-mobile", visible: :visible)
  end
end
