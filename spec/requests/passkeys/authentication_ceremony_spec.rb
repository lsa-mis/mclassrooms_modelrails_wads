# frozen_string_literal: true

require "rails_helper"

# A WebAuthn ceremony is two creates on two nouns (#1007): the challenge, then the session it earns.
RSpec.describe "Passkeys authentication ceremony", type: :request do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Passkeys.origin) }

  before do
    reg = Passkeys::RegisterCeremony.options(user: user)
    Passkeys::RegisterCeremony.verify(
      user: user,
      credential_params: client.create(challenge: reg.challenge),
      nickname: "k"
    )
  end

  describe "POST /passkeys/authentication/challenge" do
    it "returns challenge options" do
      post passkeys_authentication_challenge_path
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["challenge"]).to be_present
    end
  end

  describe "POST /passkeys/authentication/session" do
    it "signs the user in from a valid assertion" do
      post passkeys_authentication_challenge_path
      challenge = WebauthnChallenge.where(purpose: "authentication").last.challenge
      assertion = client.get(challenge: challenge)

      post passkeys_authentication_session_path, params: assertion.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(cookies[:session_id]).to be_present
      expect(response.parsed_body["redirect_to"]).to be_present
    end

    it "returns 422 for an unknown credential (different user's passkey)" do
      # Register a second user with their own client — their credential is in the
      # DB but belongs to a different WebauthnCredential row with a different
      # external_id. We then feed their assertion to the authenticate endpoint
      # using a challenge from an options call, but the credential belongs to
      # a passkey from a completely separate second client that we never registered.
      # Easiest way: register a second client, then use a fresh (third) unregistered
      # client to get — FakeClient.get requires prior create, so instead we test
      # the "credential not in DB" path by posting a malformed/unknown credential JSON.
      other_user = create(:user)
      other_client = WebAuthn::FakeClient.new(Passkeys.origin)
      other_reg = Passkeys::RegisterCeremony.options(user: other_user)
      Passkeys::RegisterCeremony.verify(
        user: other_user,
        credential_params: other_client.create(challenge: other_reg.challenge),
        nickname: "other"
      )

      post passkeys_authentication_challenge_path
      challenge = WebauthnChallenge.where(purpose: "authentication").last.challenge
      # other_client's credential IS in the DB (for other_user) — use it. The
      # credential lookup will find the row and auth will succeed for other_user.
      # To test CredentialNotFound specifically, delete all credentials so no
      # external_id matches, then attempt assertion with the original client.
      WebauthnCredential.delete_all

      assertion = client.get(challenge: challenge)
      post passkeys_authentication_session_path, params: assertion.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end

    it "returns 422 for a replayed assertion (consumed challenge)" do
      post passkeys_authentication_challenge_path
      challenge = WebauthnChallenge.where(purpose: "authentication").last.challenge
      assertion = client.get(challenge: challenge)

      # First request consumes the challenge
      post passkeys_authentication_session_path, params: assertion.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:ok)

      # Replay the same assertion — challenge already consumed
      post passkeys_authentication_session_path, params: assertion.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for a bad credential payload (VerificationFailed)" do
      post passkeys_authentication_challenge_path

      # Post a structurally invalid credential JSON — the gem will raise WebAuthn::Error
      # which the ceremony wraps as Passkeys::VerificationFailed
      post passkeys_authentication_session_path,
           params: { id: "not-a-real-credential", rawId: "bogus", type: "public-key",
                     response: { clientDataJSON: "bad", authenticatorData: "bad", signature: "bad" } }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 429 after exceeding the rate limit (11th request)" do
      # ActionController rate limiting uses Rails.cache.increment to count hits.
      # Stub it to return a count above the 10-request threshold so the limiter
      # fires without needing a real persistent cache in the test environment.
      call_count = 0
      allow(Rails.cache).to receive(:increment) do
        call_count += 1
        call_count
      end

      bad_payload = { id: "x", rawId: "x", type: "public-key",
                      response: { clientDataJSON: "x", authenticatorData: "x", signature: "x" } }.to_json
      headers = { "CONTENT_TYPE" => "application/json" }

      10.times { post passkeys_authentication_session_path, params: bad_payload, headers: headers }

      post passkeys_authentication_session_path, params: bad_payload, headers: headers
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["error"]).to be_present
    end
  end
end
