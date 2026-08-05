require "rails_helper"

# MiClassrooms Phase 4 Task 11 (Brief §5.3, §14.1): the admin bulk-upload
# flow — stateless two-step (unconfirmed review, then confirmed commit) over
# DIRECT-UPLOADED blobs, resolved by signed id (never carried as multipart
# form data across these two requests). Mirrors spec/requests/buildings_spec.rb's
# tenancy setup (shared-posture stub + workspace-scoped fixtures + sign_in)
# and reuses the "an admin-only action" shared example.
RSpec.describe "Admin bulk uploads", type: :request do
  let(:workspace) { create(:workspace, slug: "bulk-uploads-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  # Any real file works as the upload `io:` — Matcher (Task 10) reads only
  # `blob.filename.to_s`, and Room's content_type validation reads the
  # explicit `content_type:` given here, not bytes sniffed from `io`. Real
  # fixture files with the LITERAL expected names (MLB1200.jpg,
  # MLB1200_chairs.pdf, stray.txt) exist for the system spec, which drives a
  # real browser file picker and therefore can't rename a file on upload;
  # request specs have no such constraint, so this helper is free to reuse
  # one small fixture for every declared filename.
  def signed_blob(filename:, content_type:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: filename, content_type: content_type
    )
    blob.signed_id
  end

  let(:building) { create(:building, workspace: workspace) }
  let!(:room) { create(:room, workspace: workspace, building: building, facility_code: "MLB1200") }

  describe "GET /admin/bulk_uploads/new" do
    it_behaves_like "an admin-only action" do
      let(:actor) { membership_with("viewer") }
      let(:http_method) { :get }
      let(:request_path) { new_admin_bulk_upload_path }
    end

    it "returns 200 for an admin" do
      sign_in(membership_with("admin"))

      get new_admin_bulk_upload_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/bulk_uploads" do
    it_behaves_like "an admin-only action" do
      let(:actor) { membership_with("viewer") }
      let(:http_method) { :post }
      let(:request_path) { admin_bulk_uploads_path }
      let(:request_params) { { signed_blob_ids: [] } }
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "renders the review step with the correct matched/unmatched split, unconfirmed" do
        photo_id = signed_blob(filename: "MLB1200.jpg", content_type: "image/jpeg")
        stray_id = signed_blob(filename: "stray.txt", content_type: "text/plain")

        post admin_bulk_uploads_path, params: { signed_blob_ids: [ photo_id, stray_id ] }

        # 422, not 200 (see BulkUploadsController#create's comment): this app
        # runs Turbo Drive site-wide, which requires a non-redirect form
        # response to carry a 4xx/5xx status or the browser never navigates.
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("MLB1200.jpg")
        expect(response.body).to include("stray.txt")
        expect(response.body).to include(I18n.t("admin.bulk_uploads.review.reason.unrecognized_filename"))
        # Unconfirmed: nothing attached or purged yet.
        expect(room.reload.gallery).to be_empty
      end

      it "shows a replace warning in the review step when the matched has_one slot is already attached" do
        room.panorama.attach(io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
                             filename: "old.png", content_type: "image/png")
        pano_id = signed_blob(filename: "MLB1200_pano.jpg", content_type: "image/jpeg")

        post admin_bulk_uploads_path, params: { signed_blob_ids: [ pano_id ] }

        expect(response.body).to include(I18n.t("admin.bulk_uploads.review.will_replace"))
      end

      # A bare image resolves to :gallery, a has_many — nothing is overwritten,
      # so the review step must promise an APPEND, never a replace, even when
      # the room already has gallery photos.
      it "promises an append (never a replace) in the review step for a gallery match" do
        create(:media_asset, owner: room, workspace: workspace)
        photo_id = signed_blob(filename: "MLB1200.jpg", content_type: "image/jpeg")

        post admin_bulk_uploads_path, params: { signed_blob_ids: [ photo_id ] }

        expect(response.body).to include(I18n.t("admin.bulk_uploads.review.will_append"))
        expect(response.body).not_to include(I18n.t("admin.bulk_uploads.review.will_replace"))
      end

      it "attaches every matched slot and writes one ActivityLog per match, and purges unmatched blobs, on confirm" do
        photo_id = signed_blob(filename: "MLB1200.jpg", content_type: "image/jpeg")
        chairs_id = signed_blob(filename: "MLB1200_chairs.pdf", content_type: "application/pdf")
        stray_id = signed_blob(filename: "stray.txt", content_type: "text/plain")

        expect {
          post admin_bulk_uploads_path, params: {
            signed_blob_ids: [ photo_id, chairs_id, stray_id ], confirmed: "1"
          }
        }.to change(ActivityLog, :count).by(2)
          .and have_enqueued_job(ActiveStorage::PurgeJob)

        expect(response).to redirect_to(new_admin_bulk_upload_path)
        follow_redirect!
        expect(response.body).to include(I18n.t("admin.bulk_uploads.create.committed", count: 2))

        room.reload
        expect(room.gallery.count).to eq(1)
        expect(room.seating_chart).to be_attached

        logs = ActivityLog.where(action: "room.media_bulk_uploaded", trackable: room)
        expect(logs.count).to eq(2)
      end

      it "purges a matched blob that fails Room's own validation instead of leaving it orphaned, and reports the honest attached count" do
        # MLB1200.jpg matches `room`'s facility code for :gallery (Matcher only
        # reads the filename), but its byte_size trips MediaAsset's own
        # `size: { less_than_or_equal_to: 10.megabytes }` validation
        # (app/models/media_asset.rb), which the nested-attributes cascade
        # surfaces on the parent — so Curation::Apply's `save!` raises
        # RecordInvalid, which it rescues into Result.failure and rolls back.
        # Real (allowed) PNG bytes padded past the 10MB cap, rather than a
        # bogus declared content_type: `ActiveStorage::Blob.create_and_upload!`
        # IDENTIFIES the content_type from the actual bytes by default
        # (`identify: true`), so a declared-but-not-actual content_type would
        # silently be corrected to the real (valid) one and never fail
        # validation at all — byte_size is the one property that can't be
        # sniffed away.
        #
        # Before the fix, BulkUploadsController#commit never checked
        # Curation::Apply's Result: the blob was neither attached NOR purged
        # (an orphan), and the notice still counted it via
        # `@report.matched.size`.
        oversized_png = File.binread(Rails.root.join("spec/fixtures/files/avatar.png")) +
          ("\0" * (11.megabytes))
        oversized_photo_id = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(oversized_png), filename: "MLB1200.jpg", content_type: "image/png"
        ).signed_id
        chairs_id = signed_blob(filename: "MLB1200_chairs.pdf", content_type: "application/pdf")

        expect {
          post admin_bulk_uploads_path, params: {
            signed_blob_ids: [ oversized_photo_id, chairs_id ], confirmed: "1"
          }
        }.to change(ActivityLog, :count).by(1)
          .and have_enqueued_job(ActiveStorage::PurgeJob)

        expect(response).to redirect_to(new_admin_bulk_upload_path)
        follow_redirect!
        expect(response.body).to include(
          I18n.t("admin.bulk_uploads.create.partial_failure", attached: 1, failed: 1)
        )

        room.reload
        expect(room.gallery).to be_empty
        expect(room.seating_chart).to be_attached
      end

      it "replaces an already-attached has_one slot instead of erroring" do
        room.panorama.attach(io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
                             filename: "old.png", content_type: "image/png")
        pano_id = signed_blob(filename: "MLB1200_pano.jpg", content_type: "image/jpeg")

        post admin_bulk_uploads_path, params: { signed_blob_ids: [ pano_id ], confirmed: "1" }

        expect(response).to redirect_to(new_admin_bulk_upload_path)
        expect(room.reload.panorama.filename.to_s).to eq("MLB1200_pano.jpg")
      end

      # The gallery counterpart of the replace test above: a second bare image
      # for the same room ADDS a row at the next free position rather than
      # displacing the one already there.
      it "appends a gallery match after the room's existing assets" do
        existing = create(:media_asset, owner: room, workspace: workspace, position: 1)
        photo_id = signed_blob(filename: "MLB1200.jpg", content_type: "image/jpeg")

        post admin_bulk_uploads_path, params: { signed_blob_ids: [ photo_id ], confirmed: "1" }

        expect(response).to redirect_to(new_admin_bulk_upload_path)
        room.reload
        expect(room.gallery.count).to eq(2)
        expect(room.gallery.last.position).to eq(2)
        expect(room.gallery.last.image.filename.to_s).to eq("MLB1200.jpg")
        expect(existing.reload.image).to be_attached
      end

      it "attaches nothing and writes no ActivityLog when every dropped file is unmatched" do
        stray_id = signed_blob(filename: "stray.txt", content_type: "text/plain")

        expect {
          post admin_bulk_uploads_path, params: { signed_blob_ids: [ stray_id ], confirmed: "1" }
        }.not_to change(ActivityLog, :count)

        expect(response).to redirect_to(new_admin_bulk_upload_path)
      end

      it "purges every unmatched blob in a batch, not just the first" do
        stray_blob = ActiveStorage::Blob.create_and_upload!(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "stray.txt", content_type: "text/plain"
        )
        another_stray_blob = ActiveStorage::Blob.create_and_upload!(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "also_stray.txt", content_type: "text/plain"
        )

        expect {
          post admin_bulk_uploads_path, params: {
            signed_blob_ids: [ stray_blob.signed_id, another_stray_blob.signed_id ], confirmed: "1"
          }
        }.to have_enqueued_job(ActiveStorage::PurgeJob).with(stray_blob)
          .and have_enqueued_job(ActiveStorage::PurgeJob).with(another_stray_blob)

        expect(response).to redirect_to(new_admin_bulk_upload_path)
      end

      it "skips a tampered signed id instead of raising" do
        expect {
          post admin_bulk_uploads_path, params: { signed_blob_ids: [ "not-a-real-signed-id" ] }
        }.not_to raise_error

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(I18n.t("admin.bulk_uploads.review.no_matched"))
        expect(response.body).to include(I18n.t("admin.bulk_uploads.review.no_unmatched"))
      end
    end
  end
end
