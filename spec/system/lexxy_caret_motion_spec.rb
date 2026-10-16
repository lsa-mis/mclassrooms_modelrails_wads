# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The rich-text editor's block caret", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let!(:resource) { create(:resource, project: project, resourceable: create(:document), created_by: user) }

  before { sign_in_via_form(user) }

  # Lexical draws this element beside a block it cannot put a text caret next to; it is planted
  # here because Lexxy's spacer paragraphs leave no such spot in ordinary content.
  def caret_animation
    page.evaluate_script(<<~JS)
      (() => {
        const caret = document.createElement("div");
        caret.setAttribute("data-lexical-cursor", "true");
        caret.contentEditable = "false";
        document.querySelector("lexxy-editor .lexxy-editor__content").append(caret);
        const name = getComputedStyle(caret).animationName;
        caret.remove();
        return name;
      })()
    JS
  end

  it "blinks, and holds still under Reduce Motion" do
    visit edit_workspace_project_resource_path(workspace, project, resource)
    expect(page).to have_css("lexxy-editor .lexxy-editor__content")
    expect(caret_animation).to eq("blink")

    cdp_emulate_reduced_motion
    expect(caret_animation).to eq("none")
  end
end
