# frozen_string_literal: true

# What would stop production booting, or a first deploy finishing, found on the deploying machine.
# Reads the deploy through Kamal, .kamal/secrets included, and never touches a server: /docs/developer/deployment.
class DeployCheck
  PLACEHOLDER_SERVERS = %w[192.168.0.1 192.168.0.2].freeze

  STATUS_MARKS = { set: "✓", missing: "✗", conflict: "✗", placeholder: "⚠", optional_unset: "○", uncheckable: "–", unknown: "?" }.freeze
  HOME_LABELS = { "env" => "deploy.yml env", "credentials" => "credentials", "kamal_secret" => "Kamal secret", "dns" => "DNS", "dashboard" => "dashboard" }.freeze
  INPUTS_PAGE = "/docs/developer/required-production-config"

  def initialize(root:, destination: nil, compact: false)
    @root = Pathname(root)
    @destination = destination.presence
    @compact = compact
  end

  def refusals
    @refusals ||= unreadable_deploy ? [ unreadable_deploy ] : [ *containers.flat_map(&:refusals), proxy_refusal, catalog_refusal ].compact.uniq
  end

  def warnings
    @warnings ||= unreadable_deploy ? [] : [ *containers.flat_map(&:warnings), servers_warning, backup_volume_warning ].compact.uniq
  end

  def run(output = $stdout)
    output.puts "Checking #{[ deploy_files.join(' with '), *containers.map(&:credentials_file).uniq ].join(' and ')}"
    refusals.each { |refusal| output.puts "", refusal }
    warnings.each { |warning| output.puts "", "Warning: #{warning}" }
    print_inputs(output) unless @compact || unreadable_deploy
    output.puts "", verdict
    output.puts "Where to get each one: #{INPUTS_PAGE}" unless @compact
    refusals.empty? ? 0 : 1
  end

  private

  def verdict = refusals.empty? ? "Nothing here stops a deploy." : "#{refusals.size} #{refusals.one? ? 'problem stops' : 'problems stop'} a deploy."

  def print_inputs(output)
    rows = containers.first.inputs.map { |entry, status| [ STATUS_MARKS.fetch(status), entry.key, HOME_LABELS.fetch(entry.home), containers.first.detail(entry, status) ] }
    return if rows.empty?

    key_width = rows.map { |row| row[1].size }.max
    home_width = rows.map { |row| row[2].size }.max
    output.puts "", "Production inputs (#{@root.basename})"
    rows.each { |mark, key, home, detail| output.puts "  #{mark} #{key.ljust(key_width)}  #{home.ljust(home_width)}  #{detail}" }
  end

  def catalog
    return @catalog if defined?(@catalog)

    @catalog = RequiredProductionConfigCatalog.load(root: @root)
  rescue RequiredProductionConfigCatalog::Invalid => e
    @catalog_refusal = "Deploy check failed: #{e.message}"
    @catalog = nil
  rescue Errno::ENOENT
    @catalog_refusal = "Deploy check failed: #{RequiredProductionConfigCatalog::TEMPLATE_PATH} doesn't exist, so the production inputs can't be listed."
    @catalog = nil
  end

  def catalog_refusal
    catalog
    @catalog_refusal
  end

  def deploy_files = [ "config/deploy.yml", (@destination && "config/deploy.#{@destination}.yml") ].compact

  def containers
    read_deploy unless defined?(@containers)
    @containers
  end

  def unreadable_deploy
    containers
    @unreadable_deploy
  end

  # Required here, not at the top: lib/ is eager loaded in production, which has no use for Kamal.
  def read_deploy
    require "kamal"
    envs = Dir.chdir(@root) do
      @kamal = Kamal::Configuration.create_from(config_file: Pathname("config/deploy.yml"), destination: @destination)
      @kamal.roles.flat_map { |role| role.hosts.map { |host| role.env(host) } }
            .map { |env| [ env.to_h, env.secret_keys.map { |name| name.split(":").first } ] }.uniq
    end
    @containers = envs.map { |env, secret_names| Container.new(@root, env, catalog, secret_names:) }
  rescue StandardError => e
    @containers = []
    @unreadable_deploy = "Deploy check failed: Kamal can't read this deploy: #{e.message.strip}\n\n" \
      "bin/kamal deploy stops on the same thing. Details: /docs/developer/deployment"
  end

  def proxy_refusal
    return unless forces_ssl?
    return if @kamal.proxy_roles.none? { |role| !role.ssl? && role.hosts.one? && proxy_faces_the_internet?(role.hosts.first) }

    <<~MSG
      Deploy check failed: config/deploy.yml has no proxy with ssl: true, but production forces HTTPS.

      config.assume_ssl and config.force_ssl in config/environments/production.rb send every redirect
      to https:// and mark every cookie Secure. Without kamal-proxy's certificate nothing answers there:
      /up passes over plain HTTP, and the first redirect leads to a page that never loads.

      Fix: uncomment proxy: in config/deploy.yml, with ssl: true and host: your domain.
      Several servers behind your own load balancer aren't refused, and neither is a server in front that
      handles HTTPS once proxy.run moves kamal-proxy off port 80.
      Details: /docs/developer/deployment (SSL configuration section).
    MSG
  end

  def proxy_faces_the_internet?(host)
    run = @kamal.proxy_run(host)
    run.nil? || (run.publish? && run.http_port.to_i == Kamal::Configuration::Proxy::Run::DEFAULT_HTTP_PORT)
  end

  def forces_ssl?
    production = @root.join("config/environments/production.rb")
    production.exist? && production.read.match?(/^\s*config\.force_ssl\s*=\s*true\b/)
  end

  def servers_warning
    placeholders = @kamal.all_hosts & PLACEHOLDER_SERVERS
    return if placeholders.empty?

    "servers: still lists the template's #{placeholders.join(' and ')}. Put your server's address there."
  end

  def backup_volume_warning
    paths = containers.filter_map { |container| container.env["BACKUP_PATH"].presence }.uniq.reject { |path| mounted?(path) }
    return if paths.empty?

    "BACKUP_PATH is #{paths.join(' and ')}, but no volume in config/deploy.yml mounts it, so backups stay inside the container " \
      "and go with it on the next deploy. Uncomment the \"/srv/backups:/backups\" line under volumes:, " \
      "or mount your own folder there: /docs/developer/deployment (Back up the database section)."
  end

  def mounted?(path) = mounted_paths.any? { |mount| path.chomp("/") == mount || path.start_with?("#{mount}/") }
  def mounted_paths = Array(@kamal.raw_config.volumes).filter_map { |volume| volume.to_s.split(":")[1]&.chomp("/") }

  # One container's environment as Kamal starts it, and the credentials production opens with it.
  class Container
    UNOPENABLE = [ ActiveSupport::EncryptedFile::MissingKeyError, ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError ].freeze

    # Answers every credentials lookup, so the settings in config/deploy.yml still get checked when credentials can't be read.
    module AssumedCredentials
      def self.dig(*) = "assumed"
    end

    # Opens with the key Kamal hands the container, the only one production has: .dockerignore keeps key files out.
    class Credentials < ActiveSupport::EncryptedConfiguration
      def initialize(key:, content_path:, key_path:)
        super(config_path: content_path, key_path:, env_key: "RAILS_MASTER_KEY", raise_if_missing_key: true)
        @deploy_key = key
      end

      def key = @deploy_key.presence || handle_missing_key
    end

    attr_reader :env

    def initialize(root, env, catalog = nil, secret_names: [])
      @root = root
      @env = env
      @catalog = catalog
      @secret_names = secret_names
    end

    def refusals
      [ (unreadable_credentials unless credentials),
        *RequiredProductionConfig.refusals(@env, credentials || AssumedCredentials, {}), owner_refusal,
        *input_refusals ].compact
    end

    def inputs
      return [] unless @catalog

      @catalog.entries.map { |entry| [ entry, status_of(entry) ] }
    end

    def detail(entry, status)
      case status
      when :set then set_detail(entry)
      when :missing then "missing"
      when :placeholder then "looks like a placeholder"
      when :conflict then "#{set_detail(entry)}, which conflicts with another input above"
      when :optional_unset then "optional: #{entry.purpose}"
      when :uncheckable then "can't check from here: #{entry.where}"
      else "unknown"
      end + (entry.source == :local ? "  (from required_production_config.local.yml)" : "")
    end

    def warnings = [ backups_warning, workspace_creation_warning, undecided_preset_warning ].compact

    def credentials_file = relative(paths[:content_path])

    private

    def credentials
      return @credentials if defined?(@credentials)
      return @credentials = nil unless paths[:content_path].exist?

      @credentials = begin
        Credentials.new(key: @env["RAILS_MASTER_KEY"].to_s, **paths).config
      rescue *UNOPENABLE => e
        @credentials_error = e
        nil
      end
    end

    # Production's own choice: the deploy's RAILS_CREDENTIALS_ENV, else production's file, else the root one Rails falls back to.
    def paths
      @paths ||= DeployCredentials.paths(@env, root: @root).presence ||
        if !@root.join("config/credentials/production.yml.enc").exist? && @root.join("config/credentials.yml.enc").exist?
          { content_path: @root.join("config/credentials.yml.enc"), key_path: @root.join("config/master.key") }
        else
          { content_path: @root.join("config/credentials/production.yml.enc"), key_path: @root.join("config/credentials/production.key") }
        end
    end

    def relative(path) = path.relative_path_from(@root).to_s

    def unreadable_credentials
      reason =
        if !paths[:content_path].exist?
          "#{credentials_file} doesn't exist. bin/mail-setup creates it, with the mail login production needs."
        elsif !@env.key?("RAILS_MASTER_KEY")
          "config/deploy.yml never hands the container RAILS_MASTER_KEY, so production can't open #{credentials_file}. " \
            "List it under env.secret, as the template does."
        elsif @credentials_error.is_a?(ActiveSupport::EncryptedFile::MissingKeyError)
          "No key opens #{credentials_file}. Put it in #{relative(paths[:key_path])}, or set RAILS_MASTER_KEY."
        else
          "The key doesn't open #{credentials_file}. If RAILS_MASTER_KEY is set in this shell, " \
            "run `unset RAILS_MASTER_KEY`; otherwise get #{relative(paths[:key_path])} from whoever set this fork up."
        end
      "Deploy check failed: #{reason}\n\nThe settings stored in credentials can't be checked until it opens."
    end

    def set_detail(entry)
      return "resolves" if entry.home == "kamal_secret"

      entry.home == "env" && !entry.secret && !@secret_names.include?(entry.key) ? @env[entry.key].to_s : "set"
    end

    def status_of(entry)
      return :unknown if credentials.nil? && entry.home == "kamal_secret"

      refused_inputs.fetch(entry.key) { entry.status(env: @env, credentials: credentials, preset: preset, key_resolves: !credentials.nil?) }
    end

    # The inputs a refusal above already names, so their rows say what it says and aren't refused twice.
    def refused_inputs
      @refused_inputs ||= RequiredProductionConfig.refused_inputs(@env, credentials || AssumedCredentials, {})
                                                  .merge(owner_refusal ? { "TENANCY_OWNER_EMAIL" => :missing } : {})
    end

    def preset = ForkConfig.tenancy_env(@root, env: @env, test: false)["WORKSPACE_ON_SIGNUP"]

    def input_refusals
      inputs.filter_map do |entry, status|
        next if refused_inputs.key?(entry.key) || !%i[missing placeholder].include?(status)

        headline = status == :missing ? "#{entry.key} is missing (#{entry.home}). #{entry.purpose}" : "#{entry.key} looks like a placeholder (#{entry.home})."
        "#{headline}\nGet it: #{entry.where}\nSet it: #{entry.set_with}"
      end
    end

    def shared? = ForkConfig.tenancy_env(@root, env: @env, test: false)["WORKSPACE_ON_SIGNUP"] == "shared"

    def owner_refusal
      return unless shared? && @env["TENANCY_OWNER_EMAIL"].to_s.strip.empty?

      <<~MSG
        Deploy check failed: the shared preset needs TENANCY_OWNER_EMAIL.

        The first deploy seeds the shared workspace and its first owner, and the seeds stop without
        that owner's address, so the container never starts.

        Fix: set TENANCY_OWNER_EMAIL under env.clear in config/deploy.yml.
        Details: /docs/developer/presets-single-tenant
      MSG
    end

    def backups_warning
      return unless RequiredProductionConfig.backups_off?(@env)

      "Backups are off. Set BACKUP_PATH (a folder) or OBJECT_STORAGE_BUCKET (a bucket) under env.clear: " \
        "/docs/developer/deployment (Back up the database section)."
    end

    def workspace_creation_warning
      return unless shared? && @env["TENANCY_WORKSPACE_CREATION"] != "disabled"

      "The shared preset usually turns off creating more workspaces: TENANCY_WORKSPACE_CREATION: disabled " \
        "under env.clear. /docs/developer/presets-single-tenant"
    end

    def undecided_preset_warning
      fork = ForkConfig.read(@root)
      return unless fork.recorded? && fork.preset.nil? && @env["WORKSPACE_ON_SIGNUP"].to_s.strip.empty?

      "No tenancy preset is chosen: .fork.yml records no preset, so production starts on personal, where every new user " \
        "gets a workspace of their own. Choose one with bin/fork --preset personal|shared|none: /docs/developer/presets"
    end
  end
end
