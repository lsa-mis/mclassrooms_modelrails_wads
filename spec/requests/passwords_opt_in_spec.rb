require "rails_helper"

# The test environment turns passwords on (factory users carry one); these
# examples turn them off and redraw the routes, so the default is exercised.
RSpec.describe "Password sign-in is opt-in", type: :request do
  around do |example|
    original = Rails.configuration.x.authentication.passwords
    Rails.configuration.x.authentication.passwords = :disabled
    Rails.application.reload_routes!
    example.run
  ensure
    Rails.configuration.x.authentication.passwords = original
    Rails.application.reload_routes!
  end

  let(:user) { create(:user) } # factory password: "SecureP@ssw0rd123!"

  it "ships disabled unless AUTH_PASSWORDS says otherwise" do
    expect(Rails.root.join("config/application.rb").read)
      .to include('config.x.authentication.passwords = ENV.fetch("AUTH_PASSWORDS", "disabled").to_sym')
  end

  it "draws no password sign-in endpoint" do
    expect {
      post "/session", params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }
    }.not_to change(Session, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "draws no password reset endpoint" do
    post "/password_reset", params: { email_address: user.email_address }
    expect(response).to have_http_status(:not_found)
  end

  it "draws no password settings" do
    sign_in(user)
    get "/settings/password/new"
    expect(response).to have_http_status(:not_found)
  end

  it "offers no password form at the lookup step, even to an address that holds one" do
    post session_lookup_path, params: { email_address: user.email_address }
    expect(response.body).not_to include(I18n.t("sessions.check_email.use_password"))
    expect(response.body).not_to include('type="password"')
  end

  it "does not count a stored password as a reauthentication factor" do
    expect(user.available_reauth_factors).not_to include(:password)
  end

  it "refuses a posted password as a reauthentication" do
    sign_in(user)
    post settings_reauthentication_path, params: { password: "SecureP@ssw0rd123!" }
    expect(response).to redirect_to(new_settings_reauthentication_path)
    expect(flash[:alert]).to eq(I18n.t("settings.reauthentications.create.no_factor"))
  end

  it "lands a leftover set-password link on the signed-in home, not on missing settings" do
    token = MagicLinkToken.create_for_email(user.email_address, intent: "set_password")
    post magic_link_callback_session_path(token)
    expect(response).to redirect_to(root_path)
  end
end
