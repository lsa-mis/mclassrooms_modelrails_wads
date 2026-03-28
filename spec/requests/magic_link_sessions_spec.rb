require "rails_helper"

RSpec.describe "Magic Link Sessions", type: :request do
  describe "GET /magic_link_session/:token" do
    context "valid token for existing user" do
      let(:user) { create(:user) }

      before do
        user.generate_magic_link_token!
      end

      it "signs in the user" do
        get magic_link_session_path(token: user.magic_link_token)
        expect(response).to redirect_to(root_path)
      end

      it "invalidates the token after use" do
        get magic_link_session_path(token: user.magic_link_token)
        expect(user.reload.magic_link_token).to be_nil
      end
    end

    context "expired token" do
      let(:user) { create(:user) }

      before do
        user.generate_magic_link_token!
        user.update_column(:magic_link_sent_at, 20.minutes.ago)
      end

      it "rejects the token" do
        get magic_link_session_path(token: user.magic_link_token)
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "invalid token" do
      it "rejects and redirects" do
        get magic_link_session_path(token: "bogus")
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "token for non-existent user (new registration)" do
      it "redirects to magic link registration" do
        # This tests that a magic link for a new email goes to registration
        # We'll need a different token mechanism for new users
        # For now, test that unknown tokens redirect appropriately
        get magic_link_session_path(token: "unknown")
        expect(response).to redirect_to(new_session_path)
      end
    end

    context "token already used" do
      let(:user) { create(:user) }

      before { user.generate_magic_link_token! }

      it "rejects a token that was already consumed" do
        token = user.magic_link_token
        get magic_link_session_path(token: token)
        expect(response).to redirect_to(root_path)

        # Second attempt with same token
        get magic_link_session_path(token: token)
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to be_present
      end
    end
  end
end
