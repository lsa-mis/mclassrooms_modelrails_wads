require "rails_helper"

RSpec.describe "Authenticated home via email verification", type: :request do
  it "lands a member on root" do
    user = create(:user, :unverified_email)
    sign_in(user)
    auth = user.authentications.email.first
    token = auth.generate_token_for(:email_verification)
    post email_verification_path, params: { token: token }
    expect(response).to redirect_to(root_path)
  end
end
