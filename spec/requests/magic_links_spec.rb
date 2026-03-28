require "rails_helper"

RSpec.describe "Magic Links", type: :request do
  describe "POST /magic_link" do
    context "existing user with no password" do
      let(:user) { create(:user) }

      it "sends a magic link email" do
        # Remove password so user is passwordless
        user.update_column(:password_digest, nil)

        expect {
          post magic_link_path, params: { email_address: user.email_address }
        }.to have_enqueued_mail(MagicLinkMailer, :sign_in_link)
      end

      it "shows the same message regardless of account existence" do
        post magic_link_path, params: { email_address: user.email_address }
        expect(response).to redirect_to(new_session_path)
        expect(flash[:notice]).to eq(I18n.t("magic_links.create.check_email"))
      end
    end

    context "non-existent email" do
      it "shows the same message (no information leakage)" do
        post magic_link_path, params: { email_address: "nobody@example.com" }
        expect(response).to redirect_to(new_session_path)
        expect(flash[:notice]).to eq(I18n.t("magic_links.create.check_email"))
      end

      it "does not send an email" do
        expect {
          post magic_link_path, params: { email_address: "nobody@example.com" }
        }.not_to have_enqueued_mail
      end
    end

    context "existing user with password" do
      let(:user) { create(:user) }

      it "sends a magic link email (they can still use magic link)" do
        expect {
          post magic_link_path, params: { email_address: user.email_address }
        }.to have_enqueued_mail(MagicLinkMailer, :sign_in_link)
      end
    end
  end
end
