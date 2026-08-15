# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkeys::Reauthentications", type: :request do
  let(:user) { create(:user) }
  let(:client) { WebAuthn::FakeClient.new(Passkeys.origin) }

  def register_passkey_for(a_user, a_client)
    reg = Passkeys::RegisterCeremony.options(user: a_user)
    Passkeys::RegisterCeremony.verify(user: a_user, credential_params: a_client.create(challenge: reg.challenge), nickname: "k")
  end

  before do
    register_passkey_for(user, client)
    sign_in(user)
    user.sessions.update_all(reauthenticated_at: 1.hour.ago) # stale
  end

  it "stamps reauthentication from the current user's own passkey" do
    post passkeys_reauthentication_options_path
    challenge = WebauthnChallenge.where(purpose: "reauthentication").last.challenge
    assertion = client.get(challenge: challenge)

    post passkeys_reauthentication_verify_path, params: assertion.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(user.sessions.sole.reload.reauthenticated?).to be(true)
  end

  it "refuses another user's passkey and does not stamp reauthentication" do
    other_user = create(:user)
    other_client = WebAuthn::FakeClient.new(Passkeys.origin)
    register_passkey_for(other_user, other_client)

    post passkeys_reauthentication_options_path
    challenge = WebauthnChallenge.where(purpose: "reauthentication").last.challenge
    assertion = other_client.get(challenge: challenge)

    post passkeys_reauthentication_verify_path, params: assertion.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.sessions.sole.reload.reauthenticated?).to be(false)
  end

  it "rejects a replayed assertion (consumed challenge)" do
    post passkeys_reauthentication_options_path
    challenge = WebauthnChallenge.where(purpose: "reauthentication").last.challenge
    assertion = client.get(challenge: challenge)
    headers = { "CONTENT_TYPE" => "application/json" }

    post passkeys_reauthentication_verify_path, params: assertion.to_json, headers: headers
    expect(response).to have_http_status(:ok)

    post passkeys_reauthentication_verify_path, params: assertion.to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
  end
end
