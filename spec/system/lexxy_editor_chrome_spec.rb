# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Lexxy editor chrome", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }

  before { sign_in_via_form(user) }

  def box_height(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().height")
  end

  def outline_of(selector)
    page.evaluate_script(<<~JS)
      (function(el){ var cs = getComputedStyle(el); return [cs.outlineStyle, cs.outlineWidth, cs.outlineOffset].join(" "); })(document.querySelector(#{selector.to_json}))
    JS
  end

  it "shows a toolbar whose buttons meet the 44px target floor" do
    visit new_workspace_project_resource_path(workspace, project)

    expect(page).to have_css("lexxy-toolbar button[name='bold']")
    expect(box_height("lexxy-toolbar button[name='bold']")).to be >= 44
    expect_aaa_in_both_themes
  end

  it "rings the whole editor, not the text inside it, when the text has focus" do
    visit new_workspace_project_resource_path(workspace, project)
    find("lexxy-editor [contenteditable='true']").click

    expect(outline_of("lexxy-editor")).to eq("solid 2px 2px")
    expect(outline_of("lexxy-editor [contenteditable='true']")).to start_with("none")
  end

  it "gives the editor Lexxy's content styles" do
    visit new_workspace_project_resource_path(workspace, project)

    expect(page).to have_css("lexxy-editor.lexxy-content")
  end

  it "shows a list's markers while editing it" do
    document = create(:document, body: "<ul><li>First point</li></ul>")
    resource = create(:resource, project: project, resourceable: document, created_by: user)

    visit edit_workspace_project_resource_path(workspace, project, resource)

    expect(page).to have_css("lexxy-editor li", text: "First point")
    marker = page.evaluate_script("getComputedStyle(document.querySelector('lexxy-editor li')).listStyleType")
    expect(marker).not_to eq("none")
  end
end
