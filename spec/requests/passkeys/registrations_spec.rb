# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkeys::Registrations", type: :request do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Passkeys.origin) }

  describe "unauthenticated access" do
    it "redirects POST /passkeys/registration/options to sign in" do
      post passkeys_registration_options_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    before { sign_in(user) }

    describe "POST /passkeys/registration/options" do
      it "returns creation options with a challenge" do
        post passkeys_registration_options_path
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["challenge"]).to be_present
        expect(body["user"]).to be_present
      end
    end

    describe "reauthentication gate is hard-wired" do
      # Enrollment mints a durable, phishing-resistant credential and (unlike a
      # password change) revokes nothing — so it stays gated even when a fork
      # turns reauth off. Decision: 2026-08-12 reauth-defaults panel.
      around do |example|
        original = Rails.configuration.x.session.reauth_enabled
        Rails.configuration.x.session.reauth_enabled = false
        example.run
      ensure
        Rails.configuration.x.session.reauth_enabled = original
      end

      it "still requires a fresh factor for enrollment when reauth_enabled is false" do
        user.sessions.last.update!(reauthenticated_at: 20.minutes.ago)

        post passkeys_registration_options_path, headers: { "ACCEPT" => "application/json" }

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["reauth_required"]).to be(true)
      end

      it "allows enrollment within the reauth window even with the flag off" do
        post passkeys_registration_options_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /passkeys/registration/verify" do
      it "notifies the account that a passkey was added" do
        post passkeys_registration_options_path
        challenge = WebauthnChallenge.where(purpose: "registration").last.challenge
        credential = client.create(challenge: challenge)

        expect {
          post passkeys_registration_verify_path,
               params: credential.merge(nickname: "My Key").to_json,
               headers: { "CONTENT_TYPE" => "application/json" }
        }.to change { Noticed::Event.where(type: "PasskeyAddedNotifier").count }.by(1)
      end

      it "does not notify when verification fails (replayed credential)" do
        post passkeys_registration_options_path
        challenge = WebauthnChallenge.where(purpose: "registration").last.challenge
        credential = client.create(challenge: challenge)
        post passkeys_registration_verify_path,
             params: credential.merge(nickname: "My Key").to_json,
             headers: { "CONTENT_TYPE" => "application/json" }

        expect {
          post passkeys_registration_verify_path,
               params: credential.merge(nickname: "My Key").to_json,
               headers: { "CONTENT_TYPE" => "application/json" }
        }.not_to change { Noticed::Event.where(type: "PasskeyAddedNotifier").count }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "creates a passkey and returns 201" do
        post passkeys_registration_options_path
        challenge = WebauthnChallenge.where(purpose: "registration").last.challenge
        credential = client.create(challenge: challenge)

        expect {
          post passkeys_registration_verify_path,
               params: credential.merge(nickname: "My Key").to_json,
               headers: { "CONTENT_TYPE" => "application/json" }
        }.to change { user.webauthn_credentials.count }.by(1)

        expect(response).to have_http_status(:created)
      end

      it "returns 422 for a replayed credential (consumed challenge)" do
        post passkeys_registration_options_path
        challenge = WebauthnChallenge.where(purpose: "registration").last.challenge
        credential = client.create(challenge: challenge)

        # First verify succeeds
        post passkeys_registration_verify_path,
             params: credential.merge(nickname: "My Key").to_json,
             headers: { "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:created)

        # Replay with same credential payload (challenge already consumed) → 422
        post passkeys_registration_verify_path,
             params: credential.merge(nickname: "My Key").to_json,
             headers: { "CONTENT_TYPE" => "application/json" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to be_present
      end

      it "returns 422 for a malformed/unverifiable credential payload" do
        # Exercises the Passkeys::Error / ArgumentError → 422 path for any
        # ceremony failure (bad base64, invalid attestation, etc.)
        post passkeys_registration_options_path

        post passkeys_registration_verify_path,
             params: { id: "bad", rawId: "bad", type: "public-key",
                       response: { clientDataJSON: "notbase64!", attestationObject: "notbase64!" } }.to_json,
             headers: { "CONTENT_TYPE" => "application/json" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to be_present
      end

      it "returns 422 for a CredentialAlreadyRegistered error" do
        # Register the credential once via the direct ceremony so the DB row exists
        reg = Passkeys::RegisterCeremony.options(user: user)
        cred_payload = client.create(challenge: reg.challenge)
        Passkeys::RegisterCeremony.verify(user: user, credential_params: cred_payload, nickname: "existing")

        # Now stub the ceremony to simulate the duplicate error path through the endpoint
        allow(Passkeys::RegisterCeremony).to receive(:verify).and_raise(Passkeys::CredentialAlreadyRegistered)

        post passkeys_registration_options_path
        post passkeys_registration_verify_path,
             params: { nickname: "dup" }.to_json,
             headers: { "CONTENT_TYPE" => "application/json" }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to be_present
      end
    end
  end
end
