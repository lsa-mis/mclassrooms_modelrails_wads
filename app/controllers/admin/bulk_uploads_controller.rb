# MiClassrooms Phase 4 Task 11 (Brief §5.3, §14.1): admin bulk-upload —
# drop many media files, review the room/slot matches BulkUpload::Matcher
# (Task 10) resolves, commit. Stateless and two-step over DIRECT-UPLOADED
# blobs: multipart can't carry a file across two POSTs, so #new's dropzone
# direct-uploads every dropped file to storage FIRST (see
# app/javascript/application.js's `ActiveStorage.start()`); both #create
# requests (unconfirmed review + confirmed commit) only ever carry signed
# blob ids, never file bytes. No persisted model exists for this flow (see
# config/routes/app.rb) — #new and #create are the only two actions.
module Admin
  class BulkUploadsController < ApplicationController
    include DirectoryScoped

    def new
      authorize :bulk_upload, :new?, policy_class: Admin::BulkUploadPolicy
    end

    # Runs BulkUpload::Matcher against every blob the client claims via
    # `signed_blob_ids[]`, regardless of `confirmed`, so the confirmed branch
    # re-derives EXACTLY the same matched/unmatched split the admin reviewed
    # — the confirm form re-POSTs the identical signed ids (see
    # app/views/admin/bulk_uploads/review.html.erb), not a persisted
    # decision, so there is nothing to trust from the prior request.
    def create
      authorize :bulk_upload, :create?, policy_class: Admin::BulkUploadPolicy
      @report = BulkUpload::Matcher.call(resolve_blobs)

      if params[:confirmed] == "1"
        commit
      else
        # 422, not 200: this app runs Turbo Drive site-wide, and Turbo's own
        # form-submission handling requires a non-GET form response to be
        # EITHER a redirect OR a 4xx/5xx status — a 200 HTML render is
        # rejected client-side ("Form responses must redirect to another
        # location"), so the browser never navigates. This mirrors
        # RoomsController#update / BuildingsController#update's identical
        # `render :edit, status: :unprocessable_entity` on a validation
        # failure — the review step isn't a validation error, but it is the
        # same shape from Turbo's perspective: "don't redirect, render
        # something else instead."
        render :review, status: :unprocessable_content
      end
    end

    private

    # A bad/expired signed id (tampered param, or a blob purged between the
    # review render and the confirm submit) is rescued per-id rather than
    # failing the whole request — `find_signed!` raises
    # ActiveSupport::MessageVerifier::InvalidSignature for a signature that
    # doesn't verify, and ActiveRecord::RecordNotFound when the signature
    # verifies but the referenced blob row is gone. Either way the id is
    # simply dropped from this request's set: it can never reach the
    # ordinary admin UI (every signed id here was minted moments earlier by
    # this same flow), so silently skipping is the graceful degradation the
    # brief asks for rather than a hard failure over a single stale id.
    def resolve_blobs
      Array(params[:signed_blob_ids]).filter_map do |signed_id|
        ActiveStorage::Blob.find_signed!(signed_id)
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        nil
      end
    end

    # Each match is its own Curation::Apply.call — one audited ActivityLog
    # row per attached match (spec D13), not one per request: a batch that
    # matches two files to the same room (e.g. a photo + a seating chart)
    # writes two "room.media_bulk_uploaded" rows, one per slot actually
    # changed. Re-attaching an already-occupied slot is not special-cased —
    # has_one_attached's own replace-then-purge-the-old-blob behavior on
    # reassignment is exactly "replaces it" from the brief.
    #
    # A match's Result IS checked, unlike a plain fire-and-forget call: a
    # matched blob whose filename convention resolved a real room can still
    # fail Room's own content_type/size validation (app/models/room.rb), and
    # Curation::Apply rescues that RecordInvalid into Result.failure + rolls
    # back rather than raising. Every other Curation::Apply caller
    # (RoomsController#update, BuildingsController#update) branches on
    # `result.success?`; skipping that here would leave a rejected blob
    # ATTACHED TO NOTHING (never purged — it's in `@report.matched`, so the
    # unmatched-purge loop below never sees it) while the notice still
    # counted it as attached. So a failed match's blob is purged here too
    # (mirrors the unmatched-purge branch just below), and the notice
    # reports the real attached count, not the raw matched count.
    #
    # Unmatched blobs are purged (never left as orphaned storage) via
    # purge_later — mirrors Room's own remove_photo/remove_panorama/
    # remove_seating_chart writers (app/models/room.rb), which use the same
    # async purge rather than a synchronous `purge`.
    def commit
      attached = 0
      failed = 0

      @report.matched.each do |match|
        result = Curation::Apply.call(
          record: match.room, actor: Current.user,
          attributes: { match.slot => match.blob },
          action: "room.media_bulk_uploaded"
        )

        if result.success?
          attached += 1
        else
          failed += 1
          match.blob.purge_later
        end
      end
      @report.unmatched.each { |unmatched| unmatched.blob.purge_later }

      notice = failed.zero? ? t(".committed", count: attached) : t(".partial_failure", attached:, failed:)
      redirect_to new_admin_bulk_upload_path, notice: notice
    end
  end
end
