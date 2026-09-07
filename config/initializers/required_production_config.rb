# Refuses to boot production with configuration that comes up green and broken:
# a placeholder RAILS_HOST passes /up while every mailer link points at a domain
# this app does not control; missing encryption keys pass /up while the first
# user read raises. Deterministic checks only — a previously-healthy config
# must never fail a restart. See /docs/developer/deployment (Production
# preflight).
module RequiredProductionConfig
  # example.com is IANA-reserved (RFC 2606); `.example` is the TLD bin/fork
  # substitutes into placeholders. Neither can ever be a real deployment host.
  PLACEHOLDER_HOST = /\A(.+\.)?example(\.com)?\z/

  # The three values `bin/rails db:encryption:init` generates. Credentials are
  # the template's home for them; the config path is the environment-variable
  # alternative the Rails guide documents.
  ENCRYPTION_KEYS = %i[primary_key deterministic_key key_derivation_salt].freeze

  def self.check!(env = ENV, credentials = Rails.application.credentials,
                  encryption = Rails.application.config.active_record.encryption)
    check_host!(env)
    check_encryption_keys!(credentials, encryption)
  end

  def self.check_host!(env)
    host = env["RAILS_HOST"].to_s.strip
    return unless host.empty? || PLACEHOLDER_HOST.match?(host)

    raise <<~MSG
      Production preflight failed: RAILS_HOST is #{host.empty? ? "unset" : host.inspect}.

      Every mailer link (magic links, password resets, invitations) is built from
      RAILS_HOST, and DNS-rebinding protection (config.hosts) is derived from it.
      With a placeholder value the app boots, /up reports healthy, and nobody can
      sign in — the failure is invisible from the outside.

      Fix: set RAILS_HOST to this deployment's public hostname (e.g. app.yourdomain.com)
        - Kamal: add RAILS_HOST under env.clear in config/deploy.yml, then redeploy
        - Anything else: set the RAILS_HOST environment variable

      Details: /docs/developer/deployment (Production preflight section).
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end

  def self.check_encryption_keys!(credentials, encryption)
    missing = ENCRYPTION_KEYS.reject do |key|
      encryption[key].present? || credentials.dig(:active_record_encryption, key).present?
    end
    return if missing.empty?

    raise <<~MSG
      Production preflight failed: Active Record encryption keys are missing
      (#{missing.map { |key| "active_record_encryption.#{key}" }.join(", ")}).

      Personal data — email addresses, names, company names — is encrypted at
      rest. Without the keys the app boots and /up reports healthy, and the first
      read or write of a user raises.

      Fix: run `bin/rails db:encryption:init` and paste its block into
        bin/rails credentials:edit --environment production

      Details: /docs/developer/forking (Bootstrap secrets and configuration).
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end
end

# SECRET_KEY_BASE_DUMMY marks build-time boots (the Dockerfile's
# assets:precompile), where deployment ENV is legitimately absent.
RequiredProductionConfig.check! if Rails.env.production? && !ENV["SECRET_KEY_BASE_DUMMY"]
