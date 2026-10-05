# frozen_string_literal: true

require "rails_helper"

# Upstream's aria contract (#754, Lexxy 1.0 #1278), carried onto the fork's one rich-text form: notes.
# A server-side body error must reach the contenteditable screen readers actually read.
RSpec.describe "Lexxy editor aria contract", type: :system do
  let!(:workspace) { create(:workspace, slug: "lexxy-aria-workspace", personal: false) }
  let!(:unit) { create(:unit, workspace: workspace) }
  let!(:room) { create(:room, building: create(:building, workspace: workspace), workspace: workspace, unit: unit) }
  let(:editor) { create(:user).tap { |user| create(:editor_assignment, user: user, unit: unit) } }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    sign_in_via_form(editor)
  end

  it "carries a server-side body error onto the editable textbox" do
    form_id = ActionView::RecordIdentifier.dom_id(room, :new_note)
    field_id = "#{form_id}_note_body"

    visit room_path(room)
    within("##{form_id}") { click_button I18n.t("notes.form.create_submit") }

    expect(page).to have_css("##{field_id}-error", text: "Body can't be blank")
    within("##{form_id}") do
      expect(page).to have_css("lexxy-editor [contenteditable='true'][aria-invalid='true']")
      expect(page).to have_css("lexxy-editor [contenteditable='true'][aria-describedby~='#{field_id}-error']")
    end
  end
end
