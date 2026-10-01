# frozen_string_literal: true

require "rails_helper"

# #754 sets the body's aria contract on the <lexxy-editor> host; screen readers
# read the contenteditable inside it. Lexxy 1.0 rewrote that forwarding (#1278).
RSpec.describe "Lexxy editor aria contract", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }

  before { sign_in_via_form(user) }

  it "carries a server-side body error onto the editable textbox" do
    allow(Document).to receive(:create!) do
      doc = Document.new
      doc.errors.add(:body, "is too plain")
      raise ActiveRecord::RecordInvalid.new(doc)
    end

    visit new_workspace_project_resource_path(workspace, project)
    fill_in I18n.t("workspaces.projects.resources.new.title_label"), with: "Kickoff notes"
    find("lexxy-editor [contenteditable='true']").click
    page.driver.browser.keyboard.type("Agenda")
    click_button I18n.t("workspaces.projects.resources.new.submit")

    expect(page).to have_css("#document_body-error", text: "Body is too plain")
    expect(page).to have_css("lexxy-editor [contenteditable='true'][aria-invalid='true']")
    expect(page).to have_css("lexxy-editor [contenteditable='true'][aria-describedby~='document_body-error']")
  end
end
