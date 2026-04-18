require "rails_helper"

RSpec.describe "Account Avatars", type: :request do
  describe "unauthenticated access" do
    it "redirects PATCH /account/avatar to sign in" do
      patch account_avatar_path
      expect(response).to redirect_to(new_session_path)
    end

    it "redirects DELETE /account/avatar to sign in" do
      delete account_avatar_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:user) { create(:user) }
    before { sign_in(user) }

    describe "PATCH /account/avatar" do
      it "uploads an avatar and redirects to profile edit page" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: { avatar: file }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_source).to eq("upload")
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "rejects invalid content type" do
        file = Rack::Test::UploadedFile.new(
          StringIO.new("not an image"), "text/plain", true, original_filename: "document.txt"
        )
        patch account_avatar_path, params: { avatar: file }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar).not_to be_attached
      end

      it "rejects oversized file" do
        large_io = StringIO.new("x" * 6.megabytes)
        file = Rack::Test::UploadedFile.new(
          large_io, "image/png", true, original_filename: "oversized.png"
        )
        patch account_avatar_path, params: { avatar: file }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar).not_to be_attached
      end

      it "changes avatar source without uploading a file" do
        user.update_columns(has_gravatar: true)
        patch account_avatar_path, params: { avatar_source: "gravatar" }
        expect(user.reload.avatar_source).to eq("gravatar")
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "rejects invalid avatar source" do
        patch account_avatar_path, params: { avatar_source: "invalid" }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
      end

      it "accepts upload source even when no avatar is attached" do
        patch account_avatar_path, params: { avatar_source: "upload" }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_nil
        expect(user.reload.avatar_source).to eq("upload")
      end

      it "rejects gravatar source when user has no Gravatar" do
        user.update_columns(has_gravatar: false)
        patch account_avatar_path, params: { avatar_source: "gravatar" }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar_source).to eq("initials")
      end

      it "redirects when no params provided" do
        patch account_avatar_path
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "prioritizes file upload when both file and source are provided" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: { avatar: file, avatar_source: "gravatar" }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_source).to eq("upload")
      end
    end

    describe "PATCH /account/avatar with primary_color" do
      it "updates primary_color when switching to initials" do
        patch account_avatar_path, params: { avatar_source: "initials", primary_color: "270" }
        expect(user.reload.primary_color).to eq(270)
        expect(user.avatar_source).to eq("initials")
      end
    end

    describe "PATCH /account/avatar with cropped image" do
      it "saves both avatar and avatar_original" do
        cropped = fixture_file_upload("avatar.png", "image/png")
        original = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: {
          avatar: cropped,
          avatar_original: original,
          avatar_source: "upload",
          crop_coordinates: '{"x":10,"y":20,"w":100,"h":100}'
        }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_original).to be_attached
        expect(user.avatar_source).to eq("upload")
        metadata = user.avatar_original.blob.metadata
        expect(metadata["crop"]).to eq("x" => 10, "y" => 20, "w" => 100, "h" => 100)
      end
    end

    describe "PATCH /account/avatar (turbo_stream)" do
      it "responds with turbo stream that updates avatars and closes modal" do
        patch account_avatar_path, params: { avatar_source: "initials", primary_color: "180" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("user_avatar_profile")
        expect(response.body).to include("user_avatar_header")
        expect(response.body).to include("modal-closer")
      end
    end

    context "when avatar_source changes to initials (photo removal)" do
      before do
        user.avatar.attach(fixture_file_upload("avatar.png", "image/png"))
        user.avatar_original.attach(fixture_file_upload("avatar.png", "image/png"))
        user.update!(avatar_source: "upload")
      end

      it "purges avatar attachments and switches source to initials" do
        patch account_avatar_path, params: {
          avatar_source: "initials"
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.status).to be < 400
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_original).not_to be_attached
        expect(user.avatar_source).to eq("initials")
      end
    end

    describe "PATCH /account/avatar crop save vs hub save" do
      it "does NOT close modal when saving a crop (file present)" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: { avatar: file, avatar_source: "upload" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.body).not_to include("modal-closer")
        expect(response.body).to include("user_avatar_profile")
      end

      it "closes modal when saving source change (no file)" do
        patch account_avatar_path, params: { avatar_source: "initials" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.body).to include("modal-closer")
      end
    end

    describe "PATCH /account/avatar re-crop" do
      it "saves avatar without avatar_original on re-crop" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
        user.avatar_original.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "original.png", content_type: "image/png"
        )
        new_crop = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: {
          avatar: new_crop,
          crop_coordinates: '{"x":20,"y":30,"w":50,"h":50}'
        }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_original).to be_attached
        metadata = user.avatar_original.blob.metadata
        expect(metadata["crop"]).to eq("x" => 20, "y" => 30, "w" => 50, "h" => 50)
      end
    end

    describe "PATCH /account/avatar with crop_coordinates edge cases" do
      context "with malformed JSON" do
        it "ignores malformed JSON without crashing" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch account_avatar_path, params: {
            avatar: file,
            avatar_original: file,
            crop_coordinates: "not-valid-json{",
            avatar_source: "upload"
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          expect(response.status).to be < 500
        end
      end

      context "with coords missing required keys" do
        it "ignores coords missing required keys" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch account_avatar_path, params: {
            avatar: file,
            avatar_original: file,
            crop_coordinates: '{"foo":"bar"}',
            avatar_source: "upload"
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          expect(response.status).to be < 500
          user.reload
          expect(user.avatar_original.blob.metadata["crop"]).to be_nil
        end
      end

      context "with non-numeric coord values" do
        it "ignores coords with non-numeric values" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch account_avatar_path, params: {
            avatar: file,
            avatar_original: file,
            crop_coordinates: '{"x":"a","y":"b","w":"c","h":"d"}',
            avatar_source: "upload"
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          expect(response.status).to be < 500
          user.reload
          expect(user.avatar_original.blob.metadata["crop"]).to be_nil
        end
      end

      context "with valid coords" do
        it "stores coords when they have the expected shape" do
          file = fixture_file_upload("avatar.png", "image/png")
          patch account_avatar_path, params: {
            avatar: file,
            avatar_original: file,
            crop_coordinates: '{"x":10,"y":20,"w":100,"h":100}',
            avatar_source: "upload"
          }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

          user.reload
          expect(user.avatar_original.blob.metadata["crop"]).to eq({ "x" => 10, "y" => 20, "w" => 100, "h" => 100 })
        end
      end
    end

    context "when save fails during avatar update" do
      let(:valid_avatar) { fixture_file_upload("avatar.png", "image/png") }

      before do
        allow_any_instance_of(User).to receive(:save).and_return(false)
        allow_any_instance_of(User).to receive_message_chain(:errors, :full_messages).and_return([ "Avatar is invalid" ])
      end

      it "returns 422 turbo stream for turbo_stream requests (not a redirect)" do
        patch account_avatar_path, params: {
          avatar: valid_avatar,
          avatar_source: "upload"
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      end

      it "still redirects for non-turbo HTML requests" do
        patch account_avatar_path, params: {
          avatar: valid_avatar,
          avatar_source: "upload"
        }

        expect(response).to have_http_status(:redirect)
      end
    end

    describe "DELETE /account/avatar" do
      it "removes the avatar and falls back to initials" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        user.update_columns(avatar_source: "upload")
        delete account_avatar_path
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_source).to eq("initials")
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "handles destroy gracefully when no avatar is attached" do
        delete account_avatar_path
        expect(user.reload.avatar_source).to eq("initials")
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end

    describe "DELETE /account/avatar (turbo_stream)" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png",
          content_type: "image/png"
        )
        user.update!(avatar_source: "upload")
      end

      it "responds with turbo stream" do
        delete account_avatar_path,
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:success)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_source).to eq("initials")
      end

      it "still redirects for HTML requests" do
        delete account_avatar_path
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end

    describe "authorization" do
      it "invokes Account::AvatarPolicy#update? via Pundit" do
        expect_any_instance_of(Account::AvatarPolicy).to receive(:update?).and_call_original
        patch account_avatar_path, params: { avatar_source: "initials" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    describe "GET /account/avatar/hub" do
      it "renders the hub partial" do
        get hub_account_avatar_path(source: "initials"),
          headers: { "Turbo-Frame" => "identity-picker-hub" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("identity-picker-hub")
      end

      it "falls back to current source for invalid source param" do
        get hub_account_avatar_path(source: "invalid"),
          headers: { "Turbo-Frame" => "identity-picker-hub" }

        expect(response).to have_http_status(:ok)
      end
    end

    context "avatar_source guard on file upload" do
      let(:valid_avatar) { fixture_file_upload("avatar.png", "image/png") }

      before do
        # Simulate a user whose available sources don't include "upload"
        allow_any_instance_of(User).to receive(:available_avatar_sources).and_return(%w[gravatar initials])
      end

      it "rejects file upload when upload is not an allowed source" do
        patch account_avatar_path, params: {
          avatar: valid_avatar,
          avatar_original: valid_avatar,
          avatar_source: "upload"
        }, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_original).not_to be_attached
      end
    end

    describe "DELETE /account/avatar purges original" do
      it "purges both avatar and avatar_original" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
        user.avatar_original.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "original.png", content_type: "image/png"
        )
        user.update_columns(avatar_source: "upload")
        delete account_avatar_path
        user.reload
        expect(user.avatar).not_to be_attached
        expect(user.avatar_original).not_to be_attached
      end
    end
  end
end
