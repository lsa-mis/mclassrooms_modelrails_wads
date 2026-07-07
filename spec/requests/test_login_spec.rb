require "rails_helper"

# MiClassrooms Phase 0 Task 8: GET /test_login?token=... lets accessibility
# crawlers (Siteimprove) that cannot complete Google/Okta SSO sign in as a
# fixed test user. The route only exists when AuthConfig.test_login_enabled?
# was true at boot (see config/routes/app.rb and spec/lib/auth_config_spec.rb
# for that predicate, pinned separately without reloading routes).
#
# This file needs the route to actually be drawn to exercise the controller,
# so it reloads routes around every example with TEST_LOGIN_TOKEN set — and
# reloads again afterward to restore the route to its normal (undrawn, since
# TEST_LOGIN_TOKEN is unset in the ambient test/CI environment) state so it
# doesn't leak into other spec files.
RSpec.describe "GET /test_login", type: :request do
  TEST_TOKEN = "spec-test-login-token".freeze
  TEST_LOGIN_EMAIL = "test-login@umich.edu".freeze

  around do |example|
    original_token = ENV["TEST_LOGIN_TOKEN"]
    original_admin = ENV["TEST_LOGIN_ADMIN"]
    ENV["TEST_LOGIN_TOKEN"] = TEST_TOKEN
    Rails.application.reload_routes!

    example.run

    original_token.nil? ? ENV.delete("TEST_LOGIN_TOKEN") : ENV["TEST_LOGIN_TOKEN"] = original_token
    original_admin.nil? ? ENV.delete("TEST_LOGIN_ADMIN") : ENV["TEST_LOGIN_ADMIN"] = original_admin
    Rails.application.reload_routes!
  end

  let!(:shared_workspace) { create(:workspace, slug: "miclassrooms", name: "MiClassrooms", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(shared_workspace.slug)
    allow(Rails.configuration.x.tenancy).to receive(:shared_join_role).and_return("viewer")
  end

  describe "route presence" do
    it "is drawn when TEST_LOGIN_TOKEN is configured outside production" do
      expect(Rails.application.routes.url_helpers).to respond_to(:test_login_path)
    end
  end

  describe "with the correct token" do
    it "creates the test user, establishes a session, and redirects to root" do
      expect {
        get "/test_login", params: { token: TEST_TOKEN }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(root_path)

      user = User.find_by!(email_address: TEST_LOGIN_EMAIL)
      expect(user.first_name).to be_present
      expect(user.last_name).to be_present
      expect(user.sessions.count).to eq(1)
      expect(cookies[:session_id]).to be_present
    end

    it "joins the shared workspace as Viewer by default" do
      get "/test_login", params: { token: TEST_TOKEN }

      user = User.find_by!(email_address: TEST_LOGIN_EMAIL)
      membership = user.memberships.find_by!(workspace: shared_workspace)
      expect(membership.role.slug).to eq("viewer")
    end

    it "is idempotent: a repeated login reuses the same user and membership" do
      get "/test_login", params: { token: TEST_TOKEN }
      first_user_id = User.find_by!(email_address: TEST_LOGIN_EMAIL).id

      expect {
        get "/test_login", params: { token: TEST_TOKEN }
      }.not_to change(User, :count)

      expect(User.find_by!(email_address: TEST_LOGIN_EMAIL).id).to eq(first_user_id)
      expect(response).to redirect_to(root_path)
    end

    context "when TEST_LOGIN_ADMIN=true" do
      before { ENV["TEST_LOGIN_ADMIN"] = "true" }

      it "grants Admin membership" do
        get "/test_login", params: { token: TEST_TOKEN }

        user = User.find_by!(email_address: TEST_LOGIN_EMAIL)
        membership = user.memberships.find_by!(workspace: shared_workspace)
        expect(membership.role.slug).to eq("admin")
      end

      it "stays Admin across a repeated login (idempotent upgrade)" do
        get "/test_login", params: { token: TEST_TOKEN }
        get "/test_login", params: { token: TEST_TOKEN }

        user = User.find_by!(email_address: TEST_LOGIN_EMAIL)
        expect(user.memberships.find_by!(workspace: shared_workspace).role.slug).to eq("admin")
      end
    end

    it "downgrades back to Viewer once TEST_LOGIN_ADMIN is unset" do
      ENV["TEST_LOGIN_ADMIN"] = "true"
      get "/test_login", params: { token: TEST_TOKEN }
      user = User.find_by!(email_address: TEST_LOGIN_EMAIL)
      expect(user.memberships.find_by!(workspace: shared_workspace).role.slug).to eq("admin")

      ENV.delete("TEST_LOGIN_ADMIN")
      get "/test_login", params: { token: TEST_TOKEN }
      expect(user.memberships.find_by!(workspace: shared_workspace).role.slug).to eq("viewer")
    end
  end

  describe "with the wrong token" do
    it "404s, creates no user, and establishes no session" do
      expect {
        get "/test_login", params: { token: "wrong-token" }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:not_found)
      expect(cookies[:session_id]).to be_blank
    end
  end

  describe "with no token param" do
    it "404s and creates no user" do
      expect {
        get "/test_login"
      }.not_to change(User, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "when the configured token is unset at request time (route already drawn)" do
    it "fails closed with 404 rather than raising" do
      ENV.delete("TEST_LOGIN_TOKEN")

      expect {
        get "/test_login", params: { token: TEST_TOKEN }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:not_found)
    end
  end
end
