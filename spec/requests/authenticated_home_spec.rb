require "rails_helper"

RSpec.describe "Authenticated home via email verification", type: :request do
  it "lands a member on root" do
    user = create(:user, :with_email_auth)
    sign_in(user)
    auth = user.authentications.email.first
    token = auth.generate_token_for(:email_verification)
    get email_verification_path(token: token)
    expect(response).to redirect_to(root_path)
  end
end
