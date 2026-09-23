# frozen_string_literal: true

require "rails_helper"

# #479. The draft feature shipped declaring rich text out of scope: a
# Lexxy body was assumed to live in a hidden input, which `recover()`
# refuses to write back. That was never measured against the real editor.
#
# `<lexxy-editor>` is a FORM-ASSOCIATED custom element — it carries the
# `name`, it participates in FormData, and its `value` setter re-renders the
# editor. So `recover()`'s generic `field.value = …` branch already restores
# it; the only thing missing was a save trigger, because the editor emits
# `lexxy:change` and neither `input` nor `change`.
#
# These examples exercise the real form, not the harness — the harness has no
# editor, and a fake hidden input is exactly the wrong model of one.
RSpec.describe "Form drafts on a Lexxy-backed resource form", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let(:title_label) { I18n.t("workspaces.projects.resources.new.title_label") }
  let(:draft_key) { "project_#{project.id}:new_resource:document" }

  before { sign_in_via_form(user) }

  def type_into_editor(text)
    find("lexxy-editor [contenteditable='true']").click
    page.driver.browser.keyboard.type(text)
  end

  def status_region
    find('[data-form-draft-target="status"]', visible: :all)
  end

  it "saves the rich text body and restores it into the editor" do
    visit new_workspace_project_resource_path(workspace, project)
    fill_in title_label, with: "Kickoff notes"
    type_into_editor("Agenda for the kickoff")

    wait_for_draft(draft_key)

    # ARMED TRIPWIRE: a feature that never encrypts passes every assertion
    # below. Prove the body is in the blob and unreadable.
    blob = page.evaluate_script(
      "localStorage.getItem(#{draft_storage_key(user, draft_key).to_json})"
    )
    expect(blob).to be_present
    expect(blob).not_to include("Agenda for the kickoff")

    visit new_workspace_project_resource_path(workspace, project)
    expect(page).to have_text(I18n.t("form_draft.notice"))
    click_button I18n.t("form_draft.recover")

    expect(page).to have_field(title_label, with: "Kickoff notes")
    expect(page).to have_css("lexxy-editor [contenteditable='true']",
      text: "Agenda for the kickoff")
  end

  # The hidden `resource[type]` field is the reason this needs saying: it has
  # no visible sibling, so without `data-form-draft-ignore` every restore here
  # would announce as partial — telling a screen reader user that content was
  # left behind when the editor had in fact been refilled.
  it "announces a whole restore, not a partial one" do
    visit new_workspace_project_resource_path(workspace, project)
    fill_in title_label, with: "Kickoff notes"
    type_into_editor("Agenda for the kickoff")
    wait_for_draft(draft_key)

    visit new_workspace_project_resource_path(workspace, project)
    click_button I18n.t("form_draft.recover")

    expect(status_region).to have_text("Draft restored", wait: 3)
    expect(status_region).to have_no_text("could not be restored")
    # The count is deliberately not pinned: it reads one high, because the
    # editor's toolbar carries a named <select> that the serializer treats as
    # one of this form's fields (modelrails_ui#262). Measured, not assumed —
    # setting that select and dispatching change leaves the body untouched, so
    # the announcement is the whole of the damage.
  end

  # The editor initialises itself on connect. If that counted as a change, a
  # form nobody touched would save a draft and offer recovery on the next
  # visit — the feature turning into noise on every document page.
  it "offers nothing for a form the user never touched" do
    visit new_workspace_project_resource_path(workspace, project)
    expect(page).to have_css("lexxy-editor [contenteditable='true']")

    sleep 1 # longer than the 300ms save debounce

    expect(page).to have_no_text(I18n.t("form_draft.notice"))
    expect(
      page.evaluate_script("Object.keys(localStorage).filter(k => k.startsWith('draft:')).length")
    ).to eq(0)
  end

  # The edit form keys its draft off the form id, where the new form needs an
  # explicit key — worth exercising, because the two reach the same storage
  # key by different routes.
  it "recovers a draft on the edit form" do
    resource = create(:resource, project: project, created_by: user, title: "Original title")

    visit edit_workspace_project_resource_path(workspace, project, resource)
    fill_in I18n.t("workspaces.projects.resources.edit.title_label"), with: "Revised title"
    type_into_editor("A second pass")
    wait_for_draft("resource_#{resource.id}")

    visit edit_workspace_project_resource_path(workspace, project, resource)
    click_button I18n.t("form_draft.recover")

    expect(page).to have_field(
      I18n.t("workspaces.projects.resources.edit.title_label"), with: "Revised title"
    )
    expect(page).to have_css("lexxy-editor [contenteditable='true']", text: "A second pass")
  end

  # Axe's teardown audit reads the FINAL DOM, so this one ends with the chip
  # revealed. The harness already covers the chip itself; what is new here is
  # the chrome around it on a real form.
  it "shows the revealed notice accessibly on the resource form" do
    visit new_workspace_project_resource_path(workspace, project)
    fill_in title_label, with: "Axe state"
    wait_for_draft(draft_key)

    visit new_workspace_project_resource_path(workspace, project)
    expect(page).to have_text(I18n.t("form_draft.notice"))
  end

  it "clears the draft once the document is created" do
    visit new_workspace_project_resource_path(workspace, project)
    fill_in title_label, with: "Kickoff notes"
    type_into_editor("Agenda for the kickoff")
    wait_for_draft(draft_key)

    click_button I18n.t("workspaces.projects.resources.new.submit")
    expect(page).to have_text(I18n.t("workspaces.projects.resources.create.success"))

    visit new_workspace_project_resource_path(workspace, project)
    expect(page).to have_css("lexxy-editor [contenteditable='true']")
    expect(page).to have_no_text(I18n.t("form_draft.notice"))
  end
end
