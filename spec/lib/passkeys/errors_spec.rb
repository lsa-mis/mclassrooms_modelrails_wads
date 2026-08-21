require "rails_helper"

# The flash copy for a failed passkey ceremony is owned by the error class
# itself (Passkeys::Error#i18n_key), not by a case statement in a controller.
# These keys are the exact six the retired ApplicationController case returned —
# none may change without a matching locale move.
RSpec.describe Passkeys::Error do
  describe "#i18n_key" do
    {
      Passkeys::ChallengeExpired => "passkeys.errors.challenge_expired",
      Passkeys::CredentialNotFound => "passkeys.errors.credential_not_found",
      Passkeys::CredentialAlreadyRegistered => "passkeys.errors.credential_already_registered",
      Passkeys::ClonedAuthenticator => "passkeys.errors.cloned_authenticator",
      Passkeys::VerificationFailed => "passkeys.errors.verification_failed",
      Passkeys::Error => "passkeys.errors.unknown"
    }.each do |klass, key|
      it "maps #{klass} to #{key}" do
        expect(klass.new.i18n_key).to eq(key)
      end

      it "has a translation for #{key}" do
        expect(I18n.exists?(key)).to be(true)
      end
    end
  end
end
