# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The rich-text editor's block caret", type: :system do
  let!(:workspace) { create(:workspace, slug: "lexxy-caret-workspace", personal: false) }
  let(:admin) do
    create(:user).tap do |user|
      Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    end
  end

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    sign_in_via_form(admin)
  end

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
    visit new_admin_announcement_path(slot: "home_page")
    expect(page).to have_css("lexxy-editor .lexxy-editor__content")
    expect(caret_animation).to eq("blink")

    cdp_emulate_reduced_motion
    expect(caret_animation).to eq("none")
  end
end
