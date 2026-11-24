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
  # Where Rails mails by default; nothing listens there on a deployed host.
  LOOPBACK = /\A(localhost|127\.0\.0\.1)\z/

  # The words a typed stand-in is made of, as in REPLACE_ME, paste-here or your_api_key; a real login has others.
  STAND_IN_WORD = /me|here|this|it|with|your|my|the|value|key|secret|token|password|api|id|client|name|user|email|host|domain|app/i
  PLACEHOLDER_VALUE = /\A(<.*>|\[.*\]|(replace|paste|change|your)([_\- ](#{STAND_IN_WORD}))*|your(_[a-z]+)+|changeme|todo([: ].*)?|x{3,}|example)\z/i
  OAUTH_PROVIDERS = { google: "Google", github: "GitHub" }.freeze

  # The three values `bin/rails db:encryption:init` generates. Credentials are
  # the template's home for them; the config path is the environment-variable
  # alternative the Rails guide documents.
  ENCRYPTION_KEYS = %i[primary_key deterministic_key key_derivation_salt].freeze

  def self.check!(env = ENV, credentials = Rails.application.credentials,
                  encryption = Rails.application.config.active_record.encryption, logger: Rails.logger)
    refusal = refusals(env, credentials, encryption).first
    raise refusal if refusal
    return unless backups_off?(env)

    logger.warn("Backups are off: nothing copies the database or uploaded files anywhere. " \
      "Set BACKUP_PATH (a folder) or OBJECT_STORAGE_BUCKET (a bucket); /docs/developer/deployment (Back up the database section).")
  end

  # Every refusal, in the order a boot meets them, so a check before deploying can list them all.
  def self.refusals(env = ENV, credentials = Rails.application.credentials,
                    encryption = Rails.application.config.active_record.encryption)
    [ host_refusal(env), mail_refusal(env, credentials), oauth_refusal(credentials),
      encryption_refusal(credentials, encryption), backups_refusal(env, credentials) ].compact
  end

  # The inputs those refusals name: :missing, :placeholder, or :conflict for two backup destinations.
  def self.refused_inputs(env = ENV, credentials = Rails.application.credentials,
                          encryption = Rails.application.config.active_record.encryption)
    oauth = OAUTH_PROVIDERS.keys.map { |provider| oauth_inputs(credentials, provider) }.find(&:any?) || {}
    [ host_inputs(env), mail_inputs(env, credentials), oauth, encryption_inputs(credentials, encryption),
      backups_inputs(env, credentials) ].reduce(:merge)
  end

  def self.placeholder?(value) = value.is_a?(String) && PLACEHOLDER_VALUE.match?(value.strip)

  def self.backups_off?(env) = env.values_at("BACKUP_PATH", "OBJECT_STORAGE_BUCKET").all? { |value| value.to_s.strip.empty? }

  def self.backups_refusal(env, credentials)
    return if backups_off?(env)

    problem = backups_problem(env, credentials) or return

    <<~MSG
      Production preflight failed: #{problem}.

      A half-configured backup destination boots, /up reports healthy, and every
      backup fails.

      Fix, either way under env.clear in config/deploy.yml (Kamal), or the environment:
        - A folder, such as a NAS or a second drive passed in as a volume: BACKUP_PATH,
          with OBJECT_STORAGE_BUCKET removed
        - Or finish the bucket: OBJECT_STORAGE_REGION (and OBJECT_STORAGE_ENDPOINT for
          anything but AWS), plus object_storage.access_key_id and
          object_storage.secret_access_key in bin/rails credentials:edit --environment production

      Details: /docs/developer/deployment (Back up the database section).
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end

  def self.backups_problem(env, credentials)
    inputs = backups_inputs(env, credentials)
    return if inputs.empty?
    return "BACKUP_PATH and OBJECT_STORAGE_BUCKET are both set; a backup goes to one of them" if inputs.value?(:conflict)
    return "OBJECT_STORAGE_BUCKET is set but OBJECT_STORAGE_REGION is unset" if inputs.key?("OBJECT_STORAGE_REGION")

    "#{inputs.keys.to_sentence} #{inputs.one? ? "is" : "are"} unset in credentials"
  end

  def self.backups_inputs(env, credentials)
    return {} if backups_off?(env)

    path, bucket = env.values_at("BACKUP_PATH", "OBJECT_STORAGE_BUCKET").map { |value| value.to_s.strip }
    return { "BACKUP_PATH" => :conflict, "OBJECT_STORAGE_BUCKET" => :conflict } if path.present? && bucket.present?
    return {} if path.present?
    return { "OBJECT_STORAGE_REGION" => :missing } if env["OBJECT_STORAGE_REGION"].to_s.strip.empty?

    %i[access_key_id secret_access_key].select { |key| credentials.dig(:object_storage, key).to_s.strip.empty? }
                                       .to_h { |key| [ "object_storage.#{key}", :missing ] }
  end
  private_class_method :backups_problem, :backups_refusal, :backups_inputs

  def self.mail_refusal(env, credentials)
    problem = mail_problem(env, credentials) or return

    <<~MSG
      Production preflight failed: #{problem}.

      Sign-in is an email. Without a mail server it can log in to, the app boots,
      /up reports healthy, and every magic link, invitation and reset is a failed job.

      Fix: point SMTP_ADDRESS at your provider and put its login in credentials
        - SMTP_ADDRESS: under env.clear in config/deploy.yml (Kamal), or the environment
        - smtp.user_name and smtp.password: bin/rails credentials:edit --environment production
          (staging: RAILS_ENV=production RAILS_CREDENTIALS_ENV=staging bin/rails credentials:edit), then redeploy

      Details: /docs/developer/deployment (Configure outbound mail section).
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end

  def self.mail_problem(env, credentials)
    inputs = mail_inputs(env, credentials)
    keys = inputs.keys
    return if keys.empty?
    return "SMTP_ADDRESS is #{inputs["SMTP_ADDRESS"] == :missing ? "unset" : env["SMTP_ADDRESS"].to_s.strip.inspect}" if inputs.key?("SMTP_ADDRESS")
    return "#{keys.to_sentence} #{keys.one? ? "is" : "are"} unset in credentials" if inputs.value?(:missing)

    "#{keys.to_sentence} #{keys.one? ? "looks" : "look"} like #{keys.one? ? "a placeholder" : "placeholders"}"
  end

  def self.mail_inputs(env, credentials)
    address = env["SMTP_ADDRESS"].to_s.strip
    return { "SMTP_ADDRESS" => :missing } if address.empty?
    return { "SMTP_ADDRESS" => :placeholder } if LOOPBACK.match?(address) || PLACEHOLDER_HOST.match?(address)

    logins = %i[user_name password].to_h { |key| [ "smtp.#{key}", credentials.dig(:smtp, key) ] }
    blank = logins.select { |_name, value| value.to_s.strip.empty? }
    return blank.transform_values { :missing } if blank.any?

    logins.select { |_name, value| placeholder?(value) }.transform_values { :placeholder }
  end
  private_class_method :mail_problem, :mail_refusal, :mail_inputs

  def self.oauth_refusal(credentials)
    OAUTH_PROVIDERS.each do |provider, name|
      problem = oauth_problem(credentials, provider) or next

      return <<~MSG
        Production preflight failed: #{problem}.

        A client id in credentials turns on "Sign in with #{name}". With a placeholder
        id or no usable secret the app boots, /up reports healthy, and the button fails.

        Fix: put the real pair in bin/rails credentials:edit --environment production,
        or remove oauth.#{provider} entirely to leave "Sign in with #{name}" off.

        Details: /docs/developer/deployment (Production preflight section).
        Opting out for good: git rm config/initializers/required_production_config.rb
      MSG
    end
    nil
  end

  def self.oauth_problem(credentials, provider)
    name, status = oauth_inputs(credentials, provider).first
    return unless name
    return "#{name} looks like a placeholder" if name.end_with?(".client_id")

    "#{name} is #{status == :missing ? "unset" : "a placeholder"}, but oauth.#{provider}.client_id is set"
  end

  def self.oauth_inputs(credentials, provider)
    id = credentials.dig(:oauth, provider, :client_id)
    return {} if id.to_s.strip.empty?
    return { "oauth.#{provider}.client_id" => :placeholder } if placeholder?(id)

    secret = credentials.dig(:oauth, provider, :client_secret)
    return { "oauth.#{provider}.client_secret" => :missing } if secret.to_s.strip.empty?

    placeholder?(secret) ? { "oauth.#{provider}.client_secret" => :placeholder } : {}
  end
  private_class_method :oauth_problem, :oauth_inputs

  def self.host_inputs(env)
    host = env["RAILS_HOST"].to_s.strip
    return { "RAILS_HOST" => :missing } if host.empty?

    PLACEHOLDER_HOST.match?(host) ? { "RAILS_HOST" => :placeholder } : {}
  end

  def self.host_refusal(env)
    return if host_inputs(env).empty?

    host = env["RAILS_HOST"].to_s.strip

    <<~MSG
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

  def self.encryption_inputs(credentials, encryption)
    ENCRYPTION_KEYS.reject { |key| encryption[key].present? || credentials.dig(:active_record_encryption, key).present? }
                   .to_h { |key| [ "active_record_encryption.#{key}", :missing ] }
  end

  def self.encryption_refusal(credentials, encryption)
    missing = encryption_inputs(credentials, encryption).keys
    return if missing.empty?

    <<~MSG
      Production preflight failed: Active Record encryption keys are missing
      (#{missing.join(", ")}).

      Personal data — email addresses, names, company names — is encrypted at
      rest. Without the keys the app boots and /up reports healthy, and the first
      read or write of a user raises.

      Fix: run bin/encryption-setup, which adds the keys to the production
      credentials, then commit config/credentials/production.yml.enc.

      Details: /docs/developer/deployment#what-production-credentials-hold
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end
  private_class_method :host_refusal, :host_inputs, :encryption_refusal, :encryption_inputs
end

# SECRET_KEY_BASE_DUMMY marks build-time boots (the Dockerfile's
# assets:precompile), where deployment ENV is legitimately absent.
RequiredProductionConfig.check! if Rails.env.production? && !ENV["SECRET_KEY_BASE_DUMMY"]
