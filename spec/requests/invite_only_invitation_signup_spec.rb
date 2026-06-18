require "rails_helper"

RSpec.describe "Invite-only signup via an invitation", type: :request do
  before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

  let(:invitation) { create(:invitation) }

  it "is closed to the public" do
    get new_registration_path
    expect(response).to render_template(:closed)
  end

  it "opens the signup gate once an unauthenticated invitee has viewed the accept page" do
    get accept_invitation_path(token: invitation.token)
    expect(response).to have_http_status(:ok)

    get new_registration_path
    expect(response).to have_http_status(:ok)
    expect(response).to render_template(:new)
    expect(response).not_to render_template(:closed)
  end
end
