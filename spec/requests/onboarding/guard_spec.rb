require "rails_helper"

RSpec.describe "Onboarding guard", type: :request do
  context "under :none posture with a not-onboarded user" do
    before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

    it "redirects app pages into onboarding" do
      user = create(:user, :with_zero_workspaces)
      sign_in(user)
      get workspaces_path
      expect(response).to redirect_to(onboarding_path)
    end

    it "does not redirect the email-verification screen (escape hatch)" do
      user = create(:user, :with_zero_workspaces, :with_email_auth)
      sign_in(user)
      get new_email_verification_path
      expect(response).to have_http_status(:ok)
    end

    # Regression: the timezone beacon fires a background JSON PATCH right after
    # sign-in. Before the guard fix, redirect_to onboarding_path preserved the
    # HTTP method, landing on OnboardingsController#update which immediately
    # called user.update!(onboarded_at: ...) — marking the user onboarded before
    # they saw a single wizard step.
    it "does not funnel a non-HTML (JSON) request into the wizard dispatcher" do
      user = create(:user, :with_zero_workspaces)
      sign_in(user)
      patch settings_preferences_timezone_path,
            params: { timezone: "America/New_York" },
            as: :json
      expect(user.reload.onboarded?).to be(false),
        "guard must not redirect XHR/JSON into OnboardingsController#update"
      expect(response).not_to redirect_to(onboarding_path)
    end

    it "lets a not-onboarded user sign out" do
      user = create(:user, :with_zero_workspaces)
      sign_in(user)
      delete session_path
      # sign-out must complete (303 to new_session_path), NOT redirect to /onboarding
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(new_session_path)
      # session is terminated — a follow-up authenticated request bounces to sign-in
      get workspaces_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  it "never redirects under non-:none postures" do
    allow(TenancyConfig).to receive(:onboarding).and_return(:personal)
    user = create(:user, :with_zero_workspaces)
    sign_in(user)
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end

  it "does not redirect an already-onboarded :none user" do
    allow(TenancyConfig).to receive(:onboarding).and_return(:none)
    user = create(:user, :with_zero_workspaces, onboarded_at: Time.current)
    sign_in(user)
    get workspaces_path
    expect(response).to have_http_status(:ok)
  end
end
