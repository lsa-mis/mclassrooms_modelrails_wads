require "rails_helper"

RSpec.describe "Okta OIDC", type: :request do
  # Mirrors the global default in omniauth_callbacks_spec.rb so signup isn't
  # blocked by the invite-only gate added in Task 10.
  before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

  # MiClassrooms Task 4's shared-workspace posture (see spec/models/user_spec.rb
  # "#onboard_workspace under :shared posture with MiClassrooms' configured join
  # role"): stub the tenancy config the same way rather than relying on process
  # ENV, since WORKSPACE_ON_SIGNUP isn't loaded into the test process (no
  # dotenv gem wired into the app boot — only .env.example documents it).
  let(:shared_workspace) { create(:workspace, slug: "miclassrooms", name: "MiClassrooms", personal: false) }

  before do
    shared_workspace
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(shared_workspace.slug)
    allow(Rails.configuration.x.tenancy).to receive(:shared_join_role).and_return("viewer")
  end

  let(:okta_uid) { "okta-uid-umich-123" }

  let(:okta_auth_hash) do
    OmniAuth::AuthHash.new(
      provider: "okta",
      uid: okta_uid,
      info: {
        email: "wolverine@umich.edu",
        first_name: "Uma",
        last_name: "Wolverine",
        email_verified: true
      },
      credentials: {
        token: "okta-access-token",
        refresh_token: "okta-refresh-token",
        expires_at: 1.hour.from_now.to_i,
        id_token: "okta-id-token-abc"
      }
    )
  end

  describe "new-user provisioning" do
    before { OmniAuth.config.mock_auth[:okta] = okta_auth_hash }

    it "creates a user and an okta Authentication carrying the uid" do
      expect {
        get "/auth/okta/callback"
      }.to change(User, :count).by(1).and change(Authentication, :count).by(1)

      user = User.find_by(email_address: "wolverine@umich.edu")
      expect(user).to be_present

      auth = user.authentications.find_by(provider: "okta")
      expect(auth).to be_present
      expect(auth.uid).to eq(okta_uid)
      expect(auth).to be_verified
    end

    it "signs the user in" do
      get "/auth/okta/callback"
      expect(response).to redirect_to(root_path)
    end

    it "joins the shared workspace as Viewer (MiClassrooms' onboard_workspace posture)" do
      get "/auth/okta/callback"
      user = User.find_by(email_address: "wolverine@umich.edu")

      membership = shared_workspace.memberships.find_by(user: user)
      expect(membership).to be_present
      expect(membership.role.slug).to eq("viewer")
    end

    it "stashes the id_token in session for RP-initiated logout" do
      get "/auth/okta/callback"
      expect(session[:okta_id_token]).to eq("okta-id-token-abc")
    end
  end

  describe "repeat sign-in (find-or-create)" do
    let!(:user) { create(:user, email_address: "wolverine@umich.edu") }
    let!(:existing_auth) do
      user.authentications.create!(provider: "okta", uid: okta_uid, verified_at: Time.current)
    end

    before { OmniAuth.config.mock_auth[:okta] = okta_auth_hash }

    it "reuses the existing user instead of creating a new one" do
      expect {
        get "/auth/okta/callback"
      }.not_to change(User, :count)

      expect(user.authentications.where(provider: "okta").count).to eq(1)
      expect(response).to redirect_to(root_path)
    end
  end

  describe "signing in via Okta twice in a row" do
    before { OmniAuth.config.mock_auth[:okta] = okta_auth_hash }

    it "reuses the same user on the second callback hit" do
      get "/auth/okta/callback"
      first_user = User.find_by(email_address: "wolverine@umich.edu")
      expect(first_user).to be_present

      expect {
        get "/auth/okta/callback"
      }.not_to change(User, :count)

      expect(User.find_by(email_address: "wolverine@umich.edu").id).to eq(first_user.id)
      expect(first_user.authentications.where(provider: "okta").count).to eq(1)
    end
  end

  describe "cross-provider safety (Google is OIDC too)" do
    it "does not stash Okta logout state on a Google sign-in, even though Google's credentials also include an id_token" do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google-uid-not-okta",
        info: { email: "notokta@example.com", first_name: "Not", last_name: "Okta", email_verified: true },
        credentials: {
          token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i,
          id_token: "google-oidc-id-token"
        }
      )

      get "/auth/google_oauth2/callback"

      expect(session[:okta_id_token]).to be_nil
    end
  end

  describe "RP-initiated logout (D4)" do
    let!(:user) { create(:user, email_address: "wolverine@umich.edu") }
    let!(:existing_auth) do
      user.authentications.create!(provider: "okta", uid: okta_uid, verified_at: Time.current)
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OKTA_ISSUER").and_return("https://miclassrooms-test.okta.com")
    end

    context "when the active session originated from Okta" do
      before do
        OmniAuth.config.mock_auth[:okta] = okta_auth_hash
        get "/auth/okta/callback"
      end

      it "redirects through Okta's end_session_endpoint with id_token_hint and post_logout_redirect_uri" do
        delete session_path

        expect(response).to have_http_status(:see_other)
        expect(response.location).to start_with("https://miclassrooms-test.okta.com/v1/logout?")

        query = Rack::Utils.parse_nested_query(URI.parse(response.location).query)
        expect(query["id_token_hint"]).to eq("okta-id-token-abc")
        expect(query["post_logout_redirect_uri"]).to eq(new_session_url)
      end

      it "still terminates the local session" do
        expect { delete session_path }.to change(Session, :count).by(-1)
      end
    end

    context "when the active session did NOT originate from Okta (normal sign-out unchanged)" do
      before do
        post session_path, params: {
          email_address: user.email_address,
          password: "SecureP@ssw0rd123!"
        }
      end

      it "redirects to new_session_path exactly as before" do
        delete session_path
        expect(response).to redirect_to(new_session_path)
      end

      it "still terminates the local session" do
        expect { delete session_path }.to change(Session, :count).by(-1)
      end
    end
  end
end
