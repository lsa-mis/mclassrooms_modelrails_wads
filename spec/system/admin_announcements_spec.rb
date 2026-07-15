require "rails_helper"

# MiClassrooms Phase 5 Task 10 (Brief §14.1): admin CRUD coverage for the
# three fixed announcement slots (Admin::AnnouncementsController) — the
# home_page slot end to end (create → renders on the home page banner → edit
# → delete), plus axe AAA on the admin index, the new/edit forms, and the
# home page with the banner present. Mirrors
# spec/system/admin/unit_display_names_axe_spec.rb's tenancy setup
# (shared-posture stub + sign_in_via_form) and its
# Membership.find_by!(...).update!(role: Role.system_default!("admin"))
# re-role pattern (no :admin trait on :user — see find_a_room_spec.rb's
# CORRECTION B comment).
RSpec.describe "Admin announcements CRUD", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  let!(:workspace) { create(:workspace, slug: "admin-announcements-workspace", personal: false) }

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

  # Fills Lexxy's contenteditable region directly — see
  # spec/system/notes_live_updates_spec.rb's identical helper comment for why
  # `fill_in`-by-label can't resolve it (the `<label for=...>` targets the
  # outer `<lexxy-editor>`, not the nested `[contenteditable]` div the label
  # text is actually describing). Under Cuprite `.set` on a contenteditable
  # APPENDS rather than replacing (Playwright's cleared first), so we select
  # all existing content first — via the DOM Range API, which is
  # platform-independent unlike a Ctrl/Cmd+A chord — then type over the
  # selection so Lexxy's input listeners fire and its hidden field updates.
  def fill_in_lexxy(text)
    editor = find(".lexxy-editor__content")
    page.execute_script(<<~JS, editor)
      const el = arguments[0];
      el.focus();
      const range = document.createRange();
      range.selectNodeContents(el);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
    JS
    editor.send_keys(text)
  end

  # Reachable only by direct URL — admin nav is NOT wired to this console
  # (Brief §14.1) — every `visit` below names the path explicitly rather
  # than clicking a nav link to get here.
  it "index is axe-clean at AAA (both themes)" do
    visit admin_announcements_path

    expect(page).to have_selector("h1", text: I18n.t("admin.announcements.index.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on the announcements index:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  it "new form is axe-clean at AAA (both themes)" do
    visit new_admin_announcement_path(slot: "home_page")

    expect(page).to have_selector("h1", text: I18n.t("admin.announcements.new.title"))
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "AAA violations on the new announcement form:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  describe "with a persisted home_page announcement" do
    let!(:announcement) do
      create(:announcement, workspace: workspace, slot: "home_page", body: "Welcome back!")
    end

    it "edit form is axe-clean at AAA (both themes)" do
      visit edit_admin_announcement_path(announcement)

      expect(page).to have_selector("h1", text: I18n.t("admin.announcements.edit.title"))
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations on the edit announcement form:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    it "home page with the banner present is axe-clean at AAA (both themes)" do
      visit root_path

      expect(page).to have_content("Welcome back!")
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations on home with the announcement banner:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  it "creates, renders on home, edits, and deletes the home-page announcement" do
    visit admin_announcements_path

    within("li", text: I18n.t("announcements.slots.home_page")) do
      expect(page).to have_content(I18n.t("admin.announcements.index.empty"))
      click_link I18n.t("admin.announcements.index.create")
    end

    expect(page).to have_selector("h1", text: I18n.t("admin.announcements.new.title"))
    fill_in_lexxy("Welcome to MiClassrooms!")
    click_button I18n.t("admin.announcements.form.submit")

    expect(page).to have_current_path(admin_announcements_path)
    expect(page).to have_content(I18n.t("admin.announcements.create.success"))

    announcement = Announcement.find_by!(slot: "home_page")
    expect(announcement.body.to_plain_text).to eq("Welcome to MiClassrooms!")

    visit root_path
    expect(page).to have_content("Welcome to MiClassrooms!")

    visit admin_announcements_path
    within("li", text: I18n.t("announcements.slots.home_page")) do
      expect(page).to have_content(I18n.t("admin.announcements.index.filled"))
      click_link I18n.t("admin.announcements.index.edit")
    end

    expect(page).to have_selector("h1", text: I18n.t("admin.announcements.edit.title"))
    fill_in_lexxy("Updated welcome message!")
    click_button I18n.t("admin.announcements.form.submit")

    expect(page).to have_current_path(admin_announcements_path)
    expect(page).to have_content(I18n.t("admin.announcements.update.success"))
    expect(announcement.reload.body.to_plain_text).to eq("Updated welcome message!")

    visit root_path
    expect(page).to have_content("Updated welcome message!")
    expect(page).to have_no_content("Welcome to MiClassrooms!")

    visit admin_announcements_path
    within("li", text: I18n.t("announcements.slots.home_page")) do
      accept_confirm(I18n.t("admin.announcements.index.delete_confirm")) do
        click_button I18n.t("admin.announcements.index.delete")
      end
    end

    expect(page).to have_current_path(admin_announcements_path)
    expect(page).to have_content(I18n.t("admin.announcements.destroy.success"))
    expect(Announcement.find_by(slot: "home_page")).to be_nil

    visit root_path
    expect(page).to have_no_content("Updated welcome message!")
  end
end
