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
  end
end
