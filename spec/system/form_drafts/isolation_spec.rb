require "rails_helper"

RSpec.describe "Form draft isolation", type: :system do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }

  it "keeps two forms on one page isolated" do
    sign_in_via_form(user)
    visit "/draft_harness"
    fill_in "Title", with: "Main only"
    wait_for_draft("harness-main")
    visit "/draft_harness"
    within("#harness-main") { expect(page).to have_text(I18n.t("form_draft.notice")) }
    # have_text(..., visible: :hidden) raises ArgumentError — assert on the
    # selector's visibility instead (matches round_trip/lifecycle convention).
    within("#harness-mini") do
      expect(page).to have_selector("[data-form-draft-target='notice']", visible: :hidden)
    end
  end

  # SINGLE Capybara session on purpose (panel finding): using_session opens a
  # separate browser context with separate localStorage and passes vacuously.
  it "hides and sweeps user A's draft when user B signs in on the same browser" do
    sign_in_via_form(user)
    visit "/draft_harness"
    fill_in "Title", with: "User A private"
    wait_for_draft("harness-main")
    a_key = draft_storage_key(user, "harness-main")

    # House sign-out flow (matches user_menu_spec.rb / passkey_auth_spec.rb):
    # open the header user menu, then click the Sign out button.
    find("#user-menu-button").click
    click_button I18n.t("navigation.sign_out")
    expect(page).to have_current_path(new_session_path)

    sign_in_via_form(other)
    # The connect-time foreign-scope sweep only runs inside form-draft
    # controller#connect — visiting a draft-enabled page as B is what
    # triggers it (the sign-in/callback pages carry no form-draft controller).
    visit "/draft_harness"

    within("#harness-main") do
      expect(page).to have_selector("[data-form-draft-target='notice']", visible: :hidden)
    end
    # Affirmative sweep assertion (JS-side identity check, not Ruby be_nil —
    # localStorage.getItem returns a JS null, which Capybara/JSON marshals
    # back as Ruby nil either way, but === null is the unambiguous form).
    expect(page.evaluate_script("localStorage.getItem(#{a_key.to_json}) === null")).to be(true)
  end

  it "expires drafts after the window (Date.now override, not timing races)" do
    sign_in_via_form(user)
    visit "/draft_harness"
    fill_in "Title", with: "Old draft"
    wait_for_draft("harness-main")
    key = draft_storage_key(user, "harness-main")

    visit "/draft_harness"
    within("#harness-main") { expect(page).to have_text(I18n.t("form_draft.notice")) }

    page.execute_script("const real = Date.now(); Date.now = () => real + 49 * 60 * 60 * 1000")
    page.execute_script("document.dispatchEvent(new Event('turbo:morph'))") # re-evaluate via the morph hook

    # Notice-hidden first: it retries, and hideNotice() happens strictly after
    # the awaited readDraft deletes the expired entry — so once it holds, the
    # non-waiting === null check below is guaranteed (avoids an async race).
    expect(page).to have_selector("#harness-main [data-form-draft-target='notice']", visible: :hidden)
    expect(page.evaluate_script("localStorage.getItem(#{key.to_json}) === null")).to be(true)
  end

  it "disarms a stale tab when the draft is cleared in another tab" do
    sign_in_via_form(user)
    visit "/draft_harness"
    fill_in "Title", with: "Two tabs"
    wait_for_draft("harness-main")

    first_window = current_window
    second_window = open_new_window # same Playwright context → shared localStorage
    within_window(second_window) do
      visit "/draft_harness"
      within("#harness-main") { click_button I18n.t("form_draft.discard") }
    end
    within_window(first_window) do
      # storage event fired here: notice hidden + autosave disarmed
      fill_in "Title", with: "stale edits"
      sleep 0.5
      expect(page.evaluate_script("localStorage.getItem(#{draft_storage_key(user, 'harness-main').to_json}) === null")).to be(true)
    end
  end

  it "keeps new-vs-edit drafts separate on the project forms" do
    # Pure fallback-chain contract via the harness ids (kept alongside the
    # concrete real-form proof below).
    sign_in_via_form(user)
    visit "/draft_harness"
    expect(page.evaluate_script("window.formDraftHarness.draftKeyFor(document.querySelector('#harness-main'), '')")).to eq("harness-main")
    expect(page.evaluate_script("window.formDraftHarness.draftKeyFor(document.querySelector('#harness-mini'), '')")).to eq("harness-mini")
  end

  # Task 11 adoption proof (deferred from Task 10): the real projects/new and
  # projects/edit forms carry distinct explicit ids ("new_project" via
  # dom_id(@project), "edit_project_<id>" via dom_id(@project, :edit) —
  # form_with model: does not auto-id the <form> tag in this app, see
  # round_trip_spec's adoption note), so a draft typed on /new must never
  # surface — or leave an entry under — the /edit key for an existing project.
  it "keeps a projects/new draft from surfacing on projects/edit for an existing project" do
    workspace = user.personal_workspace
    existing_project = create(:project, workspace: workspace, created_by: user, name: "Existing Project")
    create(:project_membership, :creator, project: existing_project, user: user)

    sign_in_via_form(user)
    visit new_workspace_project_path(workspace)
    fill_in I18n.t("workspaces.projects.new.name_label"), with: "Draft-only project name"
    wait_for_draft("new_project")

    visit edit_workspace_project_path(workspace, existing_project)
    within("#edit_project_#{existing_project.id}") do
      expect(page).to have_selector("[data-form-draft-target='notice']", visible: :hidden)
    end
    expect(find_field(I18n.t("workspaces.projects.edit.name_label")).value).to eq(existing_project.name)

    edit_key = draft_storage_key(user, "edit_project_#{existing_project.id}")
    expect(page.evaluate_script("localStorage.getItem(#{edit_key.to_json}) === null")).to be(true)
  end
end
