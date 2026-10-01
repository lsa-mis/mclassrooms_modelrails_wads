# frozen_string_literal: true

require "rails_helper"

# Fork: the template drives its document form; this directory's Lexxy field is the admin
# announcement body, so the same chrome is checked there.
RSpec.describe "Lexxy editor chrome", type: :system do
  let!(:workspace) { create(:workspace, slug: "lexxy-chrome-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let(:admin) do
    user = create(:user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    user
  end

  before { sign_in_via_form(admin) }

  def box_height(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().height")
  end

  def outline_of(selector)
    page.evaluate_script(<<~JS)
      (function(el){ var cs = getComputedStyle(el); return [cs.outlineStyle, cs.outlineWidth, cs.outlineOffset].join(" "); })(document.querySelector(#{selector.to_json}))
    JS
  end

  it "shows a toolbar whose buttons meet the 44px target floor" do
    visit new_admin_announcement_path(slot: "home_page")

    expect(page).to have_css("lexxy-toolbar button[name='bold']")
    expect(box_height("lexxy-toolbar button[name='bold']")).to be >= 44
    expect_aaa_in_both_themes
  end

  it "rings the whole editor, not the text inside it, when the text has focus" do
    visit new_admin_announcement_path(slot: "home_page")
    find("lexxy-editor [contenteditable='true']").click

    expect(outline_of("lexxy-editor")).to eq("solid 2px 2px")
    expect(outline_of("lexxy-editor [contenteditable='true']")).to start_with("none")
  end

  it "shows a list's markers while editing it" do
    announcement = create(:announcement, workspace: workspace, body: "<ul><li>First point</li></ul>")

    visit edit_admin_announcement_path(announcement)

    expect(page).to have_css("lexxy-editor li", text: "First point")
    marker = page.evaluate_script("getComputedStyle(document.querySelector('lexxy-editor li')).listStyleType")
    expect(marker).not_to eq("none")
  end
end
