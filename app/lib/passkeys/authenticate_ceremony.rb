# frozen_string_literal: true

module Passkeys
  module AuthenticateCeremony
    module_function

    # Returns WebAuthn get-options and stores the challenge for later verification.
    # Sign-in (user: nil) uses an empty allow list → discoverable / usernameless
    # assertion. Re-authentication passes the current user so the allow list is
    # scoped to *their* credentials (the browser won't offer anyone else's) and
    # a distinct purpose keeps reauth challenges from being spent as sign-ins.
    def options(user: nil, purpose: "authentication")
      allow = user ? user.webauthn_credentials.kept.pluck(:external_id) : []
      opts = WebAuthn::Credential.options_for_get(user_verification: "preferred", allow: allow)
      WebauthnChallenge.store(challenge: opts.challenge, purpose: purpose, user: user)
      opts
    end

    # Verifies the assertion response, advances sign_count (clone detection),
    # and returns the authenticated User.
    #
    # Raises:
    #   Passkeys::CredentialNotFound  – external_id not in the registry
    #   Passkeys::ChallengeExpired    – challenge missing, expired, or replayed
    #   Passkeys::ClonedAuthenticator – sign_count did not advance (possible clone)
    #   Passkeys::VerificationFailed  – gem rejected the assertion
    def verify(credential_params:, expected_user: nil, purpose: "authentication")
      webauthn_credential = WebAuthn::Credential.from_get(credential_params)
      scope = WebauthnCredential.kept
      # Re-auth binds to the current user: a credential owned by anyone else is
      # treated as not found, so you can't re-authenticate someone's session
      # with your own passkey.
      scope = scope.where(user: expected_user) if expected_user
      stored = scope.find_by(external_id: webauthn_credential.id)
      raise CredentialNotFound unless stored

      ApplicationRecord.transaction do
        # client_data.challenge returns raw ASCII-8BIT bytes — re-encode to
        # the base64url string that WebauthnChallenge.store persisted.
        raw_challenge = webauthn_credential.response.client_data.challenge
        stored_challenge = WebAuthn.standard_encoder.encode(raw_challenge)
        challenge = WebauthnChallenge.consume!(stored_challenge, purpose: purpose)
        raise ChallengeExpired unless challenge

        webauthn_credential.verify(challenge.challenge, public_key: stored.public_key, sign_count: stored.sign_count)
        stored.advance_sign_count!(webauthn_credential.sign_count.to_i) # raises ClonedAuthenticator on regression
        stored.user
      end
    rescue WebAuthn::Error => e
      raise VerificationFailed, e.message
    end
  end
end
