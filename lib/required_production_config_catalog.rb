require "yaml"

# Reads the catalog of production inputs: config/required_production_config.yml,
# plus a fork's optional .local.yml. Describes what production needs, never a value.
class RequiredProductionConfigCatalog
  class Invalid < StandardError; end

  Entry = Data.define(:key, :home, :required, :secret, :purpose, :where, :set_with,
                      :regenerable, :step, :example, :owner_rule, :source) do
    def required_in?(env:, preset:, credentials: nil)
      return required == "always" unless required.is_a?(Hash)

      condition, target = required.first
      case condition
      when "when_env_set" then !blank_value?(env[target])
      when "when_env_unset" then blank_value?(env[target])
      when "when_preset" then preset.to_s == target
      when "when_credential_set" then !blank_value?(credential_value(credentials, target))
      end
    end

    def status(env:, credentials:, preset:, key_resolves:)
      case home
      when "dns", "dashboard" then :uncheckable
      when "kamal_secret" then key_resolves ? :set : absent_status(env, preset, credentials)
      when "credentials" then credential_status(env, credentials, preset)
      else status_of(env[key], env, preset, credentials)
      end
    end

    private

    # Rails reads SECRET_KEY_BASE from the environment before credentials.
    def credential_status(env, credentials, preset)
      return :set if key == "secret_key_base" && !blank_value?(env["SECRET_KEY_BASE"])

      credentials.nil? ? :unknown : status_of(credential_value(credentials, key), env, preset, credentials)
    end

    # A placeholder in an input whose condition is off switches nothing on.
    def status_of(value, env, preset, credentials)
      return absent_status(env, preset, credentials) if blank_value?(value)
      return :set unless placeholder_value?(value)

      required.is_a?(Hash) && !required_in?(env: env, preset: preset, credentials: credentials) ? :optional_unset : :placeholder
    end

    def absent_status(env, preset, credentials)
      required_in?(env: env, preset: preset, credentials: credentials) ? :missing : :optional_unset
    end

    def placeholder_value?(value) = RequiredProductionConfig.placeholder?(value) || (!example.nil? && value == example)

    def blank_value?(value) = value.nil? || (value.is_a?(String) && value.strip.empty?)

    def credential_value(credentials, path)
      path.split(".").map(&:to_sym).reduce(credentials) do |node, name|
        return nil unless node.is_a?(Hash) || node.is_a?(ActiveSupport::EncryptedConfiguration)

        node.dig(name)
      end
    end
  end

  TEMPLATE_PATH = "config/required_production_config.yml".freeze
  LOCAL_PATH = "config/required_production_config.local.yml".freeze
  HOMES = %w[env credentials kamal_secret dns dashboard].freeze
  REQUIRED_WORDS = %w[always optional].freeze
  REQUIRED_CONDITIONS = %w[when_env_set when_env_unset when_preset when_credential_set].freeze
  PRESETS = %w[shared].freeze
  OWNER_RULES = %w[host mail encryption backups owner oauth].freeze
  TEXT_FIELDS = %w[purpose where set_with].freeze
  FIELDS = (%w[home required secret step example regenerable owner_rule] + TEXT_FIELDS).freeze
  ENV_KEY = /\A[A-Z][A-Z0-9_]*\z/
  CREDENTIAL_KEY = /\A[a-z][a-z0-9_]*(\.[a-z0-9_]+)*\z/

  attr_reader :entries, :exclusions

  def self.load(root:)
    root = Pathname(root)
    template = read(root.join(TEMPLATE_PATH), TEMPLATE_PATH, source: :template)
    local_file = root.join(LOCAL_PATH)
    local = File.exist?(local_file) ? read(local_file, LOCAL_PATH, source: :local) : { entries: [], exclusions: {} }

    redefined = template[:entries].map(&:key) & local[:entries].map(&:key)
    raise Invalid, "#{LOCAL_PATH}: #{redefined.first} redefines a key the template already describes" if redefined.any?

    new(template[:entries] + local[:entries], template[:exclusions].merge(local[:exclusions]))
  end

  def self.read(path, label, source:)
    data = YAML.safe_load_file(path) || {}
    raise Invalid, "#{label}: expected a mapping at the top level" unless data.is_a?(Hash)

    unknown = data.keys - %w[inputs exclusions]
    raise Invalid, "#{label}: unknown top-level key #{unknown.first}" if unknown.any?

    inputs = data["inputs"] || {}
    raise Invalid, "#{label}: inputs must be a mapping" unless inputs.is_a?(Hash)

    { entries: inputs.map { |key, fields| build_entry(key, fields, label, source) },
      exclusions: read_exclusions(data["exclusions"] || {}, label) }
  rescue Psych::Exception => error
    raise Invalid, "#{label}: #{error.message}"
  end
  private_class_method :read

  def self.read_exclusions(exclusions, label)
    valid = exclusions.is_a?(Hash) && exclusions.all? { |name, reason| name.is_a?(String) && reason.is_a?(String) }
    raise Invalid, "#{label}: exclusions must map each name to a reason" unless valid

    exclusions
  end
  private_class_method :read_exclusions

  def self.build_entry(key, fields, label, source)
    fail_with = ->(message) { raise Invalid, "#{label}: #{key}: #{message}" }
    fail_with.call("expected a mapping of fields") unless fields.is_a?(Hash)

    unknown = fields.keys - FIELDS
    fail_with.call("unknown field #{unknown.first}") if unknown.any?
    fail_with.call("owner_rule belongs to template entries only") if source == :local && fields.key?("owner_rule")

    validate_fields(fields, fail_with)
    validate_key(key, fields["home"], fail_with)
    validate_example(fields, fail_with)

    Entry.new(key: key, home: fields["home"], required: fields["required"], secret: fields["secret"],
              purpose: fields["purpose"], where: fields["where"], set_with: fields["set_with"],
              regenerable: fields["regenerable"], step: fields["step"], example: fields["example"],
              owner_rule: fields["owner_rule"], source: source)
  end
  private_class_method :build_entry

  def self.validate_fields(fields, fail_with)
    fail_with.call("home must be one of #{HOMES.join(", ")}") unless HOMES.include?(fields["home"])
    fail_with.call("required is missing or not understood") unless valid_required?(fields["required"])
    fail_with.call("secret must be true or false") unless [ true, false ].include?(fields["secret"])
    fail_with.call("step must be an integer") unless fields["step"].is_a?(Integer)
    TEXT_FIELDS.each { |name| fail_with.call("#{name} must be text") unless text?(fields[name]) }
    fail_with.call("regenerable must be text") if fields.key?("regenerable") && !text?(fields["regenerable"])
    fail_with.call("owner_rule must be one of #{OWNER_RULES.join(", ")}") if fields.key?("owner_rule") && !OWNER_RULES.include?(fields["owner_rule"])
  end
  private_class_method :validate_fields

  def self.validate_key(key, home, fail_with)
    fail_with.call("a key is text, such as RAILS_HOST or smtp.password") unless key.is_a?(String)

    case home
    when "env", "kamal_secret" then fail_with.call("an #{home} key is an upper-case name") unless ENV_KEY.match?(key)
    when "credentials" then fail_with.call("a credentials key is a dotted path such as smtp.password") unless CREDENTIAL_KEY.match?(key)
    end
  end
  private_class_method :validate_key

  def self.validate_example(fields, fail_with)
    return unless fields["home"] == "credentials"

    fail_with.call("example must be a placeholder hint such as <from Postmark → API Tokens>") unless RequiredProductionConfig.placeholder?(fields["example"])
  end
  private_class_method :validate_example

  def self.valid_required?(value)
    return REQUIRED_WORDS.include?(value) unless value.is_a?(Hash)

    condition, target = value.first
    return false unless value.one? && REQUIRED_CONDITIONS.include?(condition)

    case condition
    when "when_preset" then PRESETS.include?(target)
    when "when_credential_set" then target.is_a?(String) && CREDENTIAL_KEY.match?(target)
    else target.is_a?(String) && ENV_KEY.match?(target)
    end
  end
  private_class_method :valid_required?

  def self.text?(value) = value.is_a?(String) && !value.strip.empty?
  private_class_method :text?

  def initialize(entries, exclusions)
    @entries = entries.freeze
    @exclusions = exclusions.freeze
  end
end
