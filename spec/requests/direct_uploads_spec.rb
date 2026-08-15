# frozen_string_literal: true

require "rails_helper"

# SEC-7: the stock ActiveStorage::DirectUploadsController inherits
# ActionController::Base — NOT ApplicationController — so the endpoint was
# open to anonymous clients, minting signed storage-write URLs from
# client-declared metadata with no type or size gate, onto the same volume
# as the SQLite databases. DirectUploadsController shadows the engine route
# with authentication + an allowlist + a byte-size cap + a rate limit.
RSpec.describe "Direct uploads gate (SEC-7)", type: :request do
  let(:user) { create(:user) }
  let(:png_args) do
    { filename: "a.png", byte_size: 1.megabyte, checksum: "abc123==", content_type: "image/png" }
  end

  it "requires authentication (the engine controller had none)" do
    expect {
      post rails_direct_uploads_path, params: { blob: png_args }
    }.not_to change { ActiveStorage::Blob.count }

    expect(response).to redirect_to(new_session_path)
  end

  context "authenticated" do
    before { sign_in(user) }

    it "mints a blob and a signed direct-upload URL for an allowed image type" do
      expect {
        post rails_direct_uploads_path, params: { blob: png_args }
      }.to change { ActiveStorage::Blob.count }.by(1)

      body = response.parsed_body
      expect(body["signed_id"]).to be_present
      expect(body.dig("direct_upload", "url")).to be_present
    end

    it "accepts application/pdf (documents are the editor's point)" do
      expect {
        post rails_direct_uploads_path,
             params: { blob: png_args.merge(filename: "a.pdf", content_type: "application/pdf") }
      }.to change { ActiveStorage::Blob.count }.by(1)
    end

    it "rejects a disallowed content type with 422 and no blob row" do
      expect {
        post rails_direct_uploads_path,
             params: { blob: png_args.merge(filename: "a.zip", content_type: "application/zip") }
      }.not_to change { ActiveStorage::Blob.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(I18n.t("direct_uploads.type_not_allowed"))
    end

    it "rejects an over-cap declared byte_size with 422 and no blob row" do
      expect {
        post rails_direct_uploads_path,
             params: { blob: png_args.merge(byte_size: 11.megabytes) }
      }.not_to change { ActiveStorage::Blob.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end

    it "rate limits uploads per user" do
      allow(Rails.cache).to receive(:increment).and_return(21)

      post rails_direct_uploads_path, params: { blob: png_args }

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
