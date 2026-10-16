# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Lexxy's alternative text dialog", type: :system do
  let!(:workspace) { create(:workspace, slug: "lexxy-alt-text-workspace", personal: false) }
  let(:admin) do
    create(:user).tap do |user|
      Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    end
  end
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: Rails.root.join("spec/fixtures/files/avatar.png").open,
      filename: "canoe.png", content_type: "image/png")
  end
  let!(:announcement) do
    url = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    create(:announcement, workspace: workspace, slot: "home_page",
      body: "<p>Trip</p>#{ActionText::Attachment.from_attachable(blob, url: url).to_html}")
  end

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    sign_in_via_form(admin)
  end

  it "takes the workspace's colours, with Save as the one filled button, in both themes" do
    visit edit_admin_announcement_path(announcement)
    find("lexxy-editor figure img").click
    find("lexxy-editor button[aria-label='Alternative text']").click
    dialog = find("lexxy-editor dialog.lexxy-alternative-text-dialog[open]")
    computed = ->(element, property) { page.evaluate_script("getComputedStyle(arguments[0]).#{property}", element) }

    %w[light dark].each do |theme|
      set_theme(theme)
      page_save = find_button(I18n.t("admin.announcements.form.submit"))
      expect([ theme, computed.(dialog.find_button("Save"), :backgroundColor) ]).to eq([ theme, computed.(page_save, :backgroundColor) ])
      expect([ theme, computed.(dialog.find_button("Cancel"), :backgroundColor) ]).to eq([ theme, "rgba(0, 0, 0, 0)" ])
    end
  end

  it "lets an author describe an image, in an AAA dialog, and the description reaches the page" do
    visit edit_admin_announcement_path(announcement)
    find("lexxy-editor figure img").click
    find("lexxy-editor button[aria-label='Alternative text']").click

    dialog = find("lexxy-editor dialog.lexxy-alternative-text-dialog[open]")
    expect(dialog.find("textarea[aria-label='Description']").value).to eq("")
    expect_aaa_in_both_themes

    dialog.find("textarea[aria-label='Description']").fill_in(with: "A red canoe on a still lake")
    dialog.click_button("Save")
    expect(page).to have_no_css("lexxy-editor dialog.lexxy-alternative-text-dialog[open]")

    click_button I18n.t("admin.announcements.form.submit")
    expect(page).to have_text(I18n.t("admin.announcements.update.success"))

    visit root_path
    expect(page).to have_css("figure.attachment img[alt='A red canoe on a still lake']")
  end

  it "reaches the dialog from the keyboard alone, through Alt+F10, and hands focus back to ALT" do
    visit edit_admin_announcement_path(announcement)
    expect(page).to have_css("lexxy-editor figure img")
    page.execute_script("arguments[0].focus()", find_button(I18n.t("admin.announcements.form.submit")))
    page.driver.browser.keyboard.type([ :shift, :tab ])
    editable = find("lexxy-editor [contenteditable='true']:focus")
    expect(page).to have_css("lexxy-editor p.provisional-paragraph.hidden")
    editable.send_keys(:down)
    expect(page).to have_css("lexxy-editor lexxy-attachment-toolbar:not([hidden])")

    editable.send_keys([ :alt, :f10 ])
    alt_button = find("lexxy-editor button[aria-label='Alternative text']")
    expect(alt_button).to match_selector(":focus")
    alt_button.send_keys(:enter)

    description = find("lexxy-editor dialog.lexxy-alternative-text-dialog[open] textarea[aria-label='Description']")
    expect(description).to match_selector(":focus")
    description.send_keys("A red canoe on a still lake", :tab, :tab, :enter)
    expect(page).to have_no_css("lexxy-editor dialog.lexxy-alternative-text-dialog[open]")
    expect(alt_button).to match_selector(":focus")

    find_button(I18n.t("admin.announcements.form.submit")).send_keys(:enter)
    expect(page).to have_text(I18n.t("admin.announcements.update.success"))
    visit root_path
    expect(page).to have_css("figure.attachment img[alt='A red canoe on a still lake']")
  end
end
