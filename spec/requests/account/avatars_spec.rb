require "rails_helper"

RSpec.describe "Account Avatars", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  describe "PATCH /account/avatar" do
    it "uploads an avatar" do
      file = fixture_file_upload("avatar.png", "image/png")
      patch account_avatar_path, params: { user: { avatar: file } }
      expect(user.reload.avatar).to be_attached
    end
  end

  describe "PATCH /account/avatar with missing file" do
    it "handles missing file gracefully" do
      patch account_avatar_path, params: { user: {} }
      expect(response).to redirect_to(edit_account_profile_path)
    end
  end

  describe "DELETE /account/avatar" do
    it "removes the avatar" do
      user.avatar.attach(io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")), filename: "avatar.png")
      delete account_avatar_path
      expect(user.reload.avatar).not_to be_attached
    end
  end
end
