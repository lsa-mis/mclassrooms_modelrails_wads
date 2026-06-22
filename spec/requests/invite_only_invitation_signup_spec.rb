require "rails_helper"

RSpec.describe "Invite-only signup via an invitation", type: :request do
  before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

  let(:invitation) { create(:invitation) }

  it "redirects an unauthenticated visitor to sign-in (not a closed registration page)" do
    post accept_invitation_path(token: invitation.token)
    expect(response).to redirect_to(new_session_path)
  end

  it "opens the signup gate once an unauthenticated invitee has viewed the accept page" do
    get accept_invitation_path(token: invitation.token)
    expect(response).to have_http_status(:ok)

    # With the gate open (session has pending_invitation_token), magic-link
    # signup proceeds. The session entry point is sessions#new (new_session_path).
    get new_session_path
    expect(response).to have_http_status(:ok)
  end
end
