require "rails_helper"

RSpec.describe "Verified OAuth account linking", type: :system do
  include ActionMailer::TestHelper

  let(:user) { create(:user, email_address: "alice@home.com", first_name: "Alice") }

  before do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google",
      uid: "google-system-1",
      info: { email: "alice.work@gmail.com", name: "Alice", first_name: "Alice", last_name: "Smith" },
      credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
    )
  end

  after do
    OmniAuth.config.mock_auth.clear
    OmniAuth.config.test_mode = false
  end

  it "links Google with mismatched email via email verification" do
    sign_in_via_form(user)

    # Trigger Google OAuth link via direct callback
    perform_enqueued_jobs do
      visit "/auth/google_oauth2/callback"
    end

    # Lands on connected accounts; pending row visible
    expect(page).to have_current_path(account_connected_accounts_path)
    expect(page).to have_text("alice.work@gmail.com")
    expect(page).to have_text(I18n.t("account.connected_accounts.index.pending_label",
                                     email: "alice.work@gmail.com"))

    # Verification email was sent to the OAuth-returned email
    delivered = ActionMailer::Base.deliveries.last
    expect(delivered).to be_present
    expect(delivered.to).to eq([ "alice.work@gmail.com" ])

    # Extract token + click verification link
    auth = user.authentications.find_by(provider: "google")
    expect(auth.verification_token).to be_present
    visit verify_account_connected_accounts_path(token: auth.verification_token)

    # Verified, redirected to connected accounts
    expect(page).to have_current_path(account_connected_accounts_path)
    expect(auth.reload).to be_verified
    expect(auth.verification_token).to be_nil
    expect(page).not_to have_text(I18n.t("account.connected_accounts.index.pending_label",
                                         email: "alice.work@gmail.com"))
  end
end
