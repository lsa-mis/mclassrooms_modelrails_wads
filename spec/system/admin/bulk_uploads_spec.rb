require "rails_helper"

# MiClassrooms Phase 4 Task 11 (Brief §5.3, §14.1): end-to-end system-spec
# coverage for the admin bulk-upload flow — AND the end-to-end proof that
# Active Storage direct upload (app/javascript/application.js's
# `ActiveStorage.start()`, wired app-wide as part of this task) actually
# works: a real Playwright browser drops real files onto the dropzone
# `<input type=file>`, direct-uploads them to the :test Disk service, and the
# resulting `signed_blob_ids[]` hidden fields carry the match through to
# #create. Mirrors spec/system/buildings_spec.rb's tenancy setup (shared-
# posture stub + workspace-scoped fixtures + sign_in_via_form) and admin
# re-role pattern.
RSpec.describe "Admin bulk uploads", type: :system do
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  let!(:workspace) { create(:workspace, slug: "directory", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  let!(:building) { create(:building, workspace: workspace, name: "Mary Lou Building") }
  let!(:room) { create(:room, building: building, workspace: workspace, facility_code: "MLB1200") }

  let(:admin) do
    user = create(:user)
    Membership.find_by!(user: user, workspace: workspace).update!(role: Role.system_default!("admin"))
    user
  end

  before { sign_in_via_form(admin) }

  it "drops files, reviews the matched/unmatched split, commits, and is accessible in both themes" do
    visit new_admin_bulk_upload_path

    expect(page).to have_selector("h1", text: I18n.t("admin.bulk_uploads.new.title"))

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    # MLB1200.jpg -> :photo, MLB1200_chairs.pdf -> :seating_chart (both match
    # `room`, its facility code), stray.txt matches no BulkUpload::Matcher
    # pattern. attach_file with an array on a `multiple` input drops all
    # three at once, the way a real admin would.
    attach_file I18n.t("admin.bulk_uploads.new.dropzone_label"),
      [
        file_fixture("MLB1200.jpg").to_s,
        file_fixture("MLB1200_chairs.pdf").to_s,
        file_fixture("stray.txt").to_s
      ]

    click_button I18n.t("admin.bulk_uploads.new.submit")

    # Reaching the review page with the right split IS the proof that direct
    # upload worked: #create only ever resolves blobs via
    # ActiveStorage::Blob.find_signed! against `signed_blob_ids[]` — this
    # page cannot render correctly from stale/multipart form data.
    expect(page).to have_selector("h1", text: I18n.t("admin.bulk_uploads.review.title"))
    expect(page).to have_content("MLB1200.jpg")
    expect(page).to have_content("MLB1200_chairs.pdf")
    expect(page).to have_content("stray.txt")
    expect(page).to have_content(I18n.t("admin.bulk_uploads.review.reason.unrecognized_filename"))
    expect(page).to have_content(I18n.t("admin.bulk_uploads.review.slot.photo"))
    expect(page).to have_content(I18n.t("admin.bulk_uploads.review.slot.seating_chart"))
    expect(page).to have_link(room.display_name, href: room_path(room))

    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"

    click_button I18n.t("admin.bulk_uploads.review.confirm")

    expect(page).to have_current_path(new_admin_bulk_upload_path)
    expect(page).to have_content(I18n.t("admin.bulk_uploads.create.committed", count: 2))

    room.reload
    expect(room.photo).to be_attached
    expect(room.seating_chart).to be_attached
  end
end
