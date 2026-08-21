# frozen_string_literal: true

module Passkeys
  # Base class for all Passkeys errors. Rescue this to catch any ceremony failure.
  #
  # Each error owns its user-facing flash copy: controllers render
  # `t(error.i18n_key)`. Subclasses derive the key from their class name
  # (ChallengeExpired → passkeys.errors.challenge_expired); the base class —
  # and only it — maps to the generic "unknown" copy.
  class Error < StandardError
    def i18n_key
      "passkeys.errors.#{i18n_slug}"
    end

    private

    def i18n_slug
      return "unknown" if instance_of?(Passkeys::Error)

      self.class.name.demodulize.underscore
    end
  end
end
