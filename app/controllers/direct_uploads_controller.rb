# frozen_string_literal: true

# Shadows the Active Storage engine's UNAUTHENTICATED direct-upload endpoint
# (SEC-7); ALLOWED_CONTENT_TYPES + MAX_BYTE_SIZE are THE fork knobs for
# rich-text uploads — see /docs/developer/security (Rich-Text Direct Uploads).
class DirectUploadsController < ApplicationController
  # The engine's BaseController sets ActiveStorage::Current.url_options per
  # request; the disk service needs it to mint the signed upload URL.
  include ActiveStorage::SetCurrent

  # Rich text legitimately wants documents; images alone is too narrow for a
  # model literally named Document. Office formats stay out by default —
  # they're a real parser surface; a fork can append them here.
  ALLOWED_CONTENT_TYPES = (ApplicationRecord::IMAGE_CONTENT_TYPES + %w[application/pdf]).freeze
  MAX_BYTE_SIZE = 10.megabytes

  # Fork: 200, not the template's 20 — admin bulk upload (media pipeline)
  # legitimately drops a building's worth of room photos in one go, and each
  # file is a separate blob POST. Still a hard cap per authenticated user.
  rate_limit to: 200, within: 3.minutes,
    by: -> { Current.user&.id || request.remote_ip },
    with: -> { render json: { error: t("direct_uploads.rate_limited") }, status: :too_many_requests }

  def create
    unless ALLOWED_CONTENT_TYPES.include?(blob_args[:content_type])
      return render json: { error: t("direct_uploads.type_not_allowed") }, status: :unprocessable_content
    end
    if blob_args[:byte_size].to_i > MAX_BYTE_SIZE
      return render json: { error: t("direct_uploads.too_large", max: max_size_for_humans) },
                    status: :unprocessable_content
    end

    blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_args)
    render json: direct_upload_json(blob)
  end

  private

  # Params/JSON shapes mirror ActiveStorage::DirectUploadsController exactly,
  # so the stock @rails/activestorage DirectUpload client (used by Lexxy)
  # needs no changes.
  def blob_args
    @blob_args ||= params.expect(blob: [ :filename, :byte_size, :checksum, :content_type, metadata: {} ])
                         .to_h.symbolize_keys
  end

  def direct_upload_json(blob)
    blob.as_json(root: false, methods: :signed_id).merge(direct_upload: {
      url: blob.service_url_for_direct_upload,
      headers: blob.service_headers_for_direct_upload
    })
  end

  def max_size_for_humans
    ActiveSupport::NumberHelper.number_to_human_size(MAX_BYTE_SIZE)
  end
end
