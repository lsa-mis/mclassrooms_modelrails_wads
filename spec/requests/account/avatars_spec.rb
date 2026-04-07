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
      it "uploads an avatar and redirects to crop page" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: { avatar: file }
        user.reload
        expect(user.avatar).to be_attached
        expect(user.avatar_source).to eq("upload")
        expect(response).to redirect_to(crop_account_avatar_path)
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

      it "rejects upload source when no avatar is attached" do
        patch account_avatar_path, params: { avatar_source: "upload" }
        expect(response).to redirect_to(edit_account_profile_path)
        expect(flash[:alert]).to be_present
        expect(user.reload.avatar_source).to eq("initials")
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

    describe "GET /account/avatar/crop" do
      it "renders the crop page when avatar is attached" do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
        get crop_account_avatar_path
        expect(response).to have_http_status(:ok)
      end

      it "redirects when no avatar is attached" do
        get crop_account_avatar_path
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end

    describe "PATCH /account/avatar/save_crop" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
      end

      it "saves crop coordinates to blob metadata" do
        patch save_crop_account_avatar_path, params: { crop: { x: 10, y: 20, w: 100, h: 100 } }
        metadata = user.avatar.blob.reload.metadata
        expect(metadata["crop"]).to eq("x" => 10, "y" => 20, "w" => 100, "h" => 100)
        expect(response).to redirect_to(edit_account_profile_path)
      end

      it "redirects when no avatar is attached" do
        user.avatar.purge
        patch save_crop_account_avatar_path, params: { crop: { x: 0, y: 0, w: 50, h: 50 } }
        expect(response).to redirect_to(edit_account_profile_path)
      end
    end

    describe "PATCH /account/avatar (turbo_stream)" do
      it "responds with turbo stream containing crop UI after upload" do
        file = fixture_file_upload("avatar.png", "image/png")
        patch account_avatar_path, params: { avatar: file },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("turbo-stream")
        expect(response.body).to include("image-cropper")
      end
    end

    describe "PATCH /account/avatar/save_crop (turbo_stream)" do
      before do
        user.avatar.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
          filename: "avatar.png", content_type: "image/png"
        )
      end

      it "responds with turbo stream that updates avatar" do
        patch save_crop_account_avatar_path,
              params: { crop: { x: 10, y: 20, w: 100, h: 100 } },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include("turbo-stream")
        expect(response.body).to include("user_avatar_profile")
        metadata = user.avatar.blob.reload.metadata
        expect(metadata["crop"]).to eq("x" => 10, "y" => 20, "w" => 100, "h" => 100)
      end
    end
  end
end
