require "rails_helper"

RSpec.describe Signupable, type: :controller do
  controller(ApplicationController) do
    include Signupable
    allow_unauthenticated_access

    def create
      user = User.new(
        email_address: params[:email_address],
        first_name: "Test",
        last_name: "User",
        password: "supersecret123",
        password_confirmation: "supersecret123"
      )

      if commit_signup_atomically(user) { |u| u.authentications.create!(provider: "email", uid: u.email_address) }
        render plain: "ok"
      else
        render plain: "fail", status: :unprocessable_entity
      end
    end

    def create_with_rollback
      user = User.new(
        email_address: params[:email_address],
        first_name: "Rollback",
        last_name: "Test",
        password: "supersecret123",
        password_confirmation: "supersecret123"
      )

      success = commit_signup_atomically(user) do |_u|
        # Simulate the magic-link race pattern: the block decides to abort.
        raise ActiveRecord::Rollback
      end

      if success
        render plain: "ok-but-rolled-back"
      else
        render plain: "fail", status: :unprocessable_entity
      end
    end
  end

  before do
    routes.draw do
      post "create" => "anonymous#create"
      post "create_with_rollback" => "anonymous#create_with_rollback"
    end
  end

  describe "#commit_signup_atomically" do
    it "returns true and commits when block succeeds" do
      post :create, params: { email_address: "new@example.com" }
      expect(response).to have_http_status(:ok)
      expect(User.find_by(email_address: "new@example.com")).to be_present
    end

    it "returns false when user.save! raises RecordInvalid" do
      post :create, params: { email_address: "not an email" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(User.find_by(email_address: "not an email")).to be_nil
    end

    it "consumes the session token on success when invitation is present" do
      invitation = create(:invitation, email: "invitee@example.com")
      session[:pending_invitation_token] = invitation.token

      post :create, params: { email_address: "invitee@example.com" }

      expect(response).to have_http_status(:ok)
      expect(invitation.reload).to be_accepted
      expect(session[:pending_invitation_token]).to be_nil
    end

    it "rolls back user creation when invitation accept! raises NotAcceptable" do
      invitation = create(:invitation, :accepted, email: "racer@example.com")
      session[:pending_invitation_token] = invitation.token

      expect {
        post :create, params: { email_address: "racer@example.com" }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to be_present
    end

    it "clears the session token on invitation NotAcceptable so a retry can't loop" do
      invitation = create(:invitation, :expired, email: "retry@example.com")
      session[:pending_invitation_token] = invitation.token

      post :create, params: { email_address: "retry@example.com" }

      # I1: the token must be dropped on any NotAcceptable (expired/revoked/
      # non-admittable) — otherwise a retry re-parks the same dead token and
      # rejects forever. The invitation itself stays in the DB (accept! guards
      # before marking consumed), reclaimable via a fresh emailed link.
      expect(session[:pending_invitation_token]).to be_nil
    end

    it "rolls back user creation when the block raises ActiveRecord::Rollback" do
      # ActiveRecord::Rollback unwinds the transaction without propagating.
      # commit_signup_atomically returns true (no exception escaped), but the
      # User is NOT persisted because the transaction rolled back.
      # This pattern is used by MagicLinkCallbacksController#create to abort
      # signup when the magic-link token race is lost.
      expect {
        post :create_with_rollback, params: { email_address: "rollback@example.com" }
      }.not_to change(User, :count)

      # The action renders "ok-but-rolled-back" because commit_signup_atomically
      # returned true (Rollback is caught silently by Rails inside the transaction).
      expect(response.body).to eq("ok-but-rolled-back")
    end
  end

  describe "#accept_pending_invitation!" do
    let(:user) { create(:user) }

    it "is a no-op when no token in session" do
      expect { controller.send(:accept_pending_invitation!, user) }.not_to raise_error
    end

    it "is a no-op when token does not match any invitation" do
      controller.session[:pending_invitation_token] = "no-such-token"
      controller.send(:accept_pending_invitation!, user)
      expect(controller.session[:pending_invitation_token]).to eq("no-such-token")
    end

    it "accepts and clears token on valid invitation" do
      invitation = create(:invitation, email: user.email_address)
      controller.session[:pending_invitation_token] = invitation.token
      controller.send(:accept_pending_invitation!, user)
      expect(invitation.reload).to be_accepted
      expect(controller.session[:pending_invitation_token]).to be_nil
    end

    it "skips a mismatched invitation without raising, clears the token, and flashes why" do
      invitation = create(:invitation, email: "invited@example.com")
      controller.session[:pending_invitation_token] = invitation.token
      # `user`'s email differs from the invitation address; a mismatch must not
      # abort the (otherwise legitimate) signup, but the user should be told the
      # invited workspace wasn't joined.
      expect {
        controller.send(:accept_pending_invitation!, user)
      }.not_to raise_error

      expect(invitation.reload).to be_pending
      expect(controller.session[:pending_invitation_token]).to be_nil
      expect(controller.flash[:alert]).to eq(I18n.t("registrations.create.invitation_email_mismatch"))
    end
  end
end
