require "rails_helper"

RSpec.describe "Email verification banner", type: :request do
  it "shows the banner to a signed-in user with an unverified email" do
    user = create(:user, :with_email_auth)
    sign_in(user)
    get root_path
    expect(response.body).to include("verify-banner")
  end

  it "hides the banner once the email is verified" do
    user = create(:user, :with_email_auth)
    user.authentications.email.first.update!(verified_at: Time.current)
    sign_in(user)
    get root_path
    expect(response.body).not_to include("verify-banner")
  end
end
