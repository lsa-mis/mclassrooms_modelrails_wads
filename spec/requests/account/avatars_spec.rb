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
  end
end
