require "rails_helper"
require "tmpdir"

# Every fixture lives in a temp root, and every key is generated here: the check never meets a real one.
RSpec.describe DeployCheck do
  around do |example|
    inherited = ENV.to_h.slice("RAILS_MASTER_KEY", "KAMAL_DESTINATION")
    ENV.delete("RAILS_MASTER_KEY")
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      example.run
    end
  ensure
    %w[RAILS_MASTER_KEY KAMAL_DESTINATION].each { |name| ENV[name] = inherited[name] }
  end

  let(:ready_env) { { "RAILS_HOST" => "app.acme.test", "SMTP_ADDRESS" => "smtp.postmarkapp.com", "BACKUP_PATH" => "/backups" } }
  let(:ready_credentials) do
    { "secret_key_base" => "base", "smtp" => { "user_name" => "token", "password" => "token" },
      "active_record_encryption" => { "primary_key" => "p", "deterministic_key" => "d", "key_derivation_salt" => "s" } }
  end
  let(:template) { Rails.root }

  def write(path, content) = @root.join(path).tap { |file| file.dirname.mkpath }.write(content)

  def deploy(env: ready_env, proxy: { "ssl" => true, "host" => "app.acme.test" }, hosts: [ "203.0.113.10" ], secret: [ "RAILS_MASTER_KEY" ],
             volumes: [ "/srv/backups:/backups" ])
    config = { "service" => "acme", "image" => "acme", "registry" => { "server" => "localhost:5555" }, "builder" => { "arch" => "amd64" },
               "servers" => { "web" => { "hosts" => hosts } }, "env" => { "clear" => env, "secret" => secret }, "volumes" => volumes }
    config["proxy"] = proxy if proxy
    write("config/deploy.yml", config.to_yaml)
  end

  def secrets(content = template.join(".kamal/secrets").read, name: "secrets") = write(".kamal/#{name}", content)

  def credentials(content = ready_credentials, name: "production", content_path: "config/credentials/#{name}.yml.enc", key_path: "config/credentials/#{name}.key")
    key = ActiveSupport::EncryptedFile.generate_key
    write(key_path, key)
    ActiveSupport::EncryptedConfiguration.new(
      config_path: @root.join(content_path), key_path: @root.join(key_path), env_key: "RAILS_MASTER_KEY", raise_if_missing_key: true
    ).write(content.to_yaml)
    key
  end

  def force_ssl(on) = write("config/environments/production.rb", "Rails.application.configure do\n  config.force_ssl = #{on}\nend\n")

  def check(destination = nil, compact: false) = described_class.new(root: @root, destination:, compact:)

  def headlines(list) = list.map { |item| item.lines.first }

  before do
    force_ssl(true)
    secrets
    write("config/required_production_config.yml", template.join("config/required_production_config.yml").read)
  end

  it "passes a configuration production boots on" do
    deploy
    credentials

    expect(check.refusals).to be_empty
    expect(check.warnings).to be_empty
  end

  it "lists every refusal at once: the boot guard's, and each input the guard hasn't reached yet" do
    deploy(env: { "OBJECT_STORAGE_BUCKET" => "app-backups" })
    credentials({})

    expect(headlines(check.refusals))
      .to contain_exactly(/RAILS_HOST is unset/, /SMTP_ADDRESS is unset/, /encryption keys are missing/, /OBJECT_STORAGE_REGION is unset/, /secret_key_base is missing/,
                          /smtp.user_name is missing/, /smtp.password is missing/,
                          /object_storage.access_key_id is missing/, /object_storage.secret_access_key is missing/)
  end

  describe "reading the deploy as Kamal does" do
    before { credentials }

    it "checks a secret's value from .kamal/secrets, under the alias env.secret gives it" do
      deploy(env: ready_env.except("RAILS_HOST"), secret: %w[RAILS_MASTER_KEY RAILS_HOST:PROD_HOST])
      secrets("#{template.join('.kamal/secrets').read}\nPROD_HOST=app.acme.test\n")

      expect(check.refusals).to be_empty

      secrets("#{template.join('.kamal/secrets').read}\nPROD_HOST=app.example.com\n")

      expect(headlines(check.refusals)).to contain_exactly(/RAILS_HOST is "app.example.com"/)
    end

    it "follows YAML anchors and ERB" do
      write("config/deploy.yml", <<~YAML)
        service: acme
        image: acme
        registry: { server: localhost:5555 }
        builder: { arch: amd64 }
        servers: { web: { hosts: [ 203.0.113.10 ] } }
        x-mail: &mail
          SMTP_ADDRESS: smtp.postmarkapp.com
        env:
          secret: [ RAILS_MASTER_KEY ]
          clear:
            <<: *mail
            RAILS_HOST: <%= "app.acme" + ".test" %>
            BACKUP_PATH: /backups
        proxy: { ssl: true, host: app.acme.test }
      YAML

      expect(check.refusals).to be_empty
    end

    it "checks each role with the env Kamal starts it with, listing a refusal they share once" do
      deploy(env: ready_env.except("RAILS_HOST", "SMTP_ADDRESS"))
      config = YAML.load_file(@root.join("config/deploy.yml"))
      config["servers"]["web"]["env"] = { "clear" => { "RAILS_HOST" => "app.acme.test" } }
      config["servers"]["job"] = { "hosts" => [ "203.0.113.11" ], "cmd" => "bin/jobs", "env" => { "clear" => { "RAILS_HOST" => "app.example.com" } } }
      write("config/deploy.yml", config.to_yaml)

      expect(headlines(check.refusals)).to contain_exactly(/RAILS_HOST is "app.example.com"/, /SMTP_ADDRESS is unset/)
    end

    it "opens the credentials with the key .kamal/secrets fetches, from a password manager or anywhere else" do
      key = @root.join("config/credentials/production.key").read
      @root.join("config/credentials/production.key").delete
      write("vault/production.key", key)
      secrets("RAILS_MASTER_KEY=$(cat vault/production.key)\n")
      deploy

      expect(check.refusals).to be_empty
    end

    it "refuses with Kamal's own message when Kamal can't read the deploy" do
      deploy(secret: %w[RAILS_MASTER_KEY SMTP_PASSWORD])

      expect(check.refusals).to contain_exactly(a_string_including("Kamal can't read", "SMTP_PASSWORD"))
      expect(check.warnings).to be_empty
    end
  end

  describe "where the credentials are" do
    it "falls back to config/credentials.yml.enc and config/master.key, as production does" do
      deploy
      credentials(content_path: "config/credentials.yml.enc", key_path: "config/master.key")
      secrets("RAILS_MASTER_KEY=$(cat config/master.key)\n")

      expect(check.refusals).to be_empty
    end

    it "checks a destination with its merged settings and its own credentials" do
      deploy
      credentials({}, name: "production")
      write("config/deploy.staging.yml", { "env" => { "clear" => { "RAILS_CREDENTIALS_ENV" => "staging" } } }.to_yaml)
      secrets(template.join(".kamal/secrets.staging").read, name: "secrets.staging")
      credentials(name: "staging")

      expect(check("staging").refusals).to be_empty
    end
  end

  describe "credentials it can't read" do
    before { deploy }

    it "says when the credentials file doesn't exist" do
      expect(check.refusals.join).to include("config/credentials/production.yml.enc doesn't exist", "bin/mail-setup")
    end

    it "still checks the settings in config/deploy.yml, and only those" do
      deploy(env: ready_env.except("RAILS_HOST"))

      expect(headlines(check.refusals)).to contain_exactly(/production.yml.enc doesn't exist/, /RAILS_HOST is unset/)
    end

    it "says where the key goes when there is none" do
      credentials
      @root.join("config/credentials/production.key").delete

      expect(check.refusals.join).to include("config/credentials/production.key", "RAILS_MASTER_KEY")
    end

    it "names the root key file for root credentials" do
      credentials(content_path: "config/credentials.yml.enc", key_path: "config/master.key")
      @root.join("config/master.key").delete

      expect(check.refusals.join).to include("No key opens config/credentials.yml.enc", "config/master.key")
    end

    it "refuses a deploy that never hands the container its key, though the key file is here" do
      credentials
      deploy(secret: [])

      expect(check.refusals.join).to include("RAILS_MASTER_KEY", "env.secret")
    end

    it "suspects an exported RAILS_MASTER_KEY when the key is wrong" do
      credentials
      ENV["RAILS_MASTER_KEY"] = ActiveSupport::EncryptedFile.generate_key

      expect(check.refusals.join).to include("doesn't open", "unset RAILS_MASTER_KEY")
    end

    it "refuses a key of the wrong length instead of stopping on it" do
      credentials
      ENV["RAILS_MASTER_KEY"] = "abc"

      expect(check.refusals.join).to include("doesn't open")
    end
  end

  describe "HTTPS" do
    before { credentials }

    it "refuses a single server with no SSL proxy while production forces HTTPS" do
      deploy(proxy: nil)

      expect(check.refusals.join).to include("proxy", "ssl: true", "force_ssl")
    end

    it "refuses a proxy whose ssl isn't on" do
      deploy(proxy: { "host" => "app.acme.test" })

      expect(check.refusals.join).to include("ssl: true")
    end

    it "accepts a proxy with its own certificate" do
      deploy(proxy: { "host" => "app.acme.test", "ssl" => { "certificate_pem" => "CERT_PEM", "private_key_pem" => "KEY_PEM" } })

      expect(check.refusals).to be_empty
    end

    it "leaves several servers to the load balancer in front of them" do
      deploy(proxy: { "host" => "app.acme.test" }, hosts: %w[203.0.113.10 203.0.113.11])

      expect(check.refusals).to be_empty
    end

    it "leaves HTTPS to a server in front when kamal-proxy moves off port 80" do
      deploy(proxy: { "ssl" => false, "host" => "app.acme.test", "run" => { "http_port" => 8080, "https_port" => 8443 } })

      expect(check.refusals).to be_empty
    end

    it "leaves HTTPS to a server in front when kamal-proxy publishes no ports" do
      deploy(proxy: { "ssl" => false, "host" => "app.acme.test", "run" => { "publish" => false } })

      expect(check.refusals).to be_empty
    end

    it "refuses ssl off while kamal-proxy keeps port 80" do
      deploy(proxy: { "ssl" => false, "host" => "app.acme.test", "run" => { "http_port" => 80, "https_port" => 8443 } })

      expect(check.refusals.join).to include("ssl: true")
    end

    it "leaves the proxy alone when production doesn't force HTTPS" do
      force_ssl(false)
      deploy(proxy: nil)

      expect(check.refusals).to be_empty
    end
  end

  describe "the shared preset" do
    before do
      write(".fork.yml", "name: acme\npreset: shared\n")
      credentials
    end

    it "refuses a first deploy that can't seed the shared workspace's owner" do
      deploy

      expect(check.refusals.join).to include("TENANCY_OWNER_EMAIL")
    end

    it "warns while workspace creation is still on" do
      deploy(env: ready_env.merge("TENANCY_OWNER_EMAIL" => "owner@acme.test"))

      expect(check.refusals).to be_empty
      expect(check.warnings.join).to include("TENANCY_WORKSPACE_CREATION")
    end

    it "doesn't warn once workspace creation is off" do
      deploy(env: ready_env.merge("TENANCY_OWNER_EMAIL" => "owner@acme.test", "TENANCY_WORKSPACE_CREATION" => "disabled"))

      expect(check.warnings).to be_empty
    end
  end

  describe "a fork that hasn't chosen a preset" do
    before { credentials }

    it "warns when .fork.yml records the fork but no preset" do
      write(".fork.yml", "name: acme\n")
      deploy

      expect(check.refusals).to be_empty
      expect(check.warnings.join).to include("no preset", "personal", "bin/fork --preset")
    end

    it "warns the same when preset: is there but empty" do
      write(".fork.yml", "name: acme\npreset:\n")
      deploy

      expect(check.refusals).to be_empty
      expect(check.warnings.join).to include("no preset", "personal", "bin/fork --preset")
    end

    it "doesn't warn when the deploy sets WORKSPACE_ON_SIGNUP" do
      write(".fork.yml", "name: acme\n")
      deploy(env: ready_env.merge("WORKSPACE_ON_SIGNUP" => "personal"))

      expect(check.warnings).to be_empty
    end

    it "doesn't warn on preset: none, which is a choice" do
      write(".fork.yml", "name: acme\npreset: none\n")
      deploy

      expect(check.warnings).to be_empty
    end
  end

  it "warns when no volume mounts BACKUP_PATH, so backups would vanish with the container" do
    deploy(volumes: [])
    credentials

    expect(check.warnings.join).to include("BACKUP_PATH is /backups", "/srv/backups:/backups")
  end

  it "accepts a volume that mounts a folder holding BACKUP_PATH" do
    deploy(env: ready_env.merge("BACKUP_PATH" => "/data/backups"), volumes: [ "/srv/data:/data" ])
    credentials

    expect(check.warnings).to be_empty
  end

  it "doesn't count a volume whose path only starts with the same letters" do
    deploy(env: ready_env.merge("BACKUP_PATH" => "/backups"), volumes: [ "/srv/b:/back" ])
    credentials

    expect(check.warnings.join).to include("BACKUP_PATH is /backups")
  end

  it "accepts a volume written with a trailing slash" do
    deploy(volumes: [ "/srv/backups:/backups/" ])
    credentials

    expect(check.warnings).to be_empty
  end

  it "checks BACKUP_PATH in every role, not only the first" do
    deploy(env: ready_env.merge("BACKUP_PATH" => "/elsewhere"))
    config = YAML.safe_load(@root.join("config/deploy.yml").read)
    config["servers"]["job"] = { "hosts" => [ "203.0.113.11" ], "cmd" => "bin/jobs", "env" => { "clear" => { "BACKUP_PATH" => "/backups" } } }
    write("config/deploy.yml", config.to_yaml)
    credentials

    expect(check.warnings.join).to include("BACKUP_PATH is /elsewhere")
  end

  it "warns about the template's placeholder server and backups being off" do
    deploy(env: ready_env.except("BACKUP_PATH"), hosts: [ "192.168.0.1" ])
    credentials

    expect(check.warnings.join).to include("192.168.0.1", "Backups are off")
  end

  it "reads the template's own deploy files, as a fork first meets them", :template_only do
    %w[config/deploy.yml config/environments/production.rb .kamal/secrets .tool-versions].each { |path| write(path, template.join(path).read) }

    expect(headlines(check.refusals)).to contain_exactly(/production.yml.enc doesn't exist/, /RAILS_HOST is unset/, /no proxy with ssl: true/)
    expect(check.warnings.join).to include("192.168.0.1", "Backups are off")
  end

  describe "#run" do
    let(:printed) { StringIO.new }

    it "prints each refusal, counts them and fails" do
      deploy(env: ready_env.except("RAILS_HOST"))
      credentials

      expect(check(compact: true).run(printed)).to eq(1)
      expect(printed.string).to include("RAILS_HOST is unset")
      expect(printed.string.lines.last.chomp).to eq("1 problem stops a deploy.")
    end

    it "prints warnings and passes when nothing is refused" do
      deploy(hosts: [ "192.168.0.1" ])
      credentials

      expect(check(compact: true).run(printed)).to eq(0)
      expect(printed.string).to include("Warning: servers: still lists the template's 192.168.0.1")
      expect(printed.string.lines.last.chomp).to eq("Nothing here stops a deploy.")
    end
  end

  describe "the production inputs" do
    let(:printed) { StringIO.new }
    let(:stripe_entry) do
      { "inputs" => { "stripe.secret_key" => { "home" => "credentials", "required" => "always", "secret" => true, "step" => 6,
                                                "purpose" => "Charges cards", "where" => "Stripe dashboard → API keys",
                                                "set_with" => "bin/rails credentials:edit --environment production",
                                                "example" => "<from Stripe>" } } }
    end

    def local_catalog(content = stripe_entry) = write("config/required_production_config.local.yml", content.to_yaml)

    before { deploy }

    it "prints the inputs table after the verdict when run by hand" do
      credentials
      local_catalog

      expect(check.run(printed)).to eq(1)
      expect(printed.string).to include("Production inputs", "✓ RAILS_HOST", "app.acme.test", "✗ stripe.secret_key",
                                        "(from required_production_config.local.yml)", "1 problem stops a deploy.",
                                        "Where to get each one: /docs/developer/required-production-config")
      expect(printed.string.index("1 problem stops")).to be > printed.string.index("Production inputs")
      expect(printed.string.lines.last.chomp).to eq("Where to get each one: /docs/developer/required-production-config")
    end

    it "stops a deploy on a placeholder in a local input" do
      credentials(ready_credentials.merge("stripe" => { "secret_key" => "<from Stripe>" }))
      local_catalog

      expect(check.refusals.join).to match(/stripe.secret_key looks like a placeholder.*\nGet it: .*\nSet it: /)
    end

    it "refuses a missing local input with where to get it and how to set it" do
      credentials
      local_catalog

      expect(check.refusals).to contain_exactly(
        "stripe.secret_key is missing (credentials). Charges cards\nGet it: Stripe dashboard → API keys\nSet it: bin/rails credentials:edit --environment production"
      )
    end

    it "omits the table in compact form but keeps the refusals" do
      credentials
      local_catalog

      expect(check(compact: true).run(printed)).to eq(1)
      expect(printed.string).not_to include("Production inputs")
      expect(printed.string).to include("stripe.secret_key is missing")
    end

    it "never prints a secret value" do
      secrets = ready_credentials.merge("stripe" => { "secret_key" => "secret-sentinel-0" })
      secrets["secret_key_base"] = "secret-sentinel-1"
      secrets["smtp"] = { "user_name" => "secret-sentinel-2", "password" => "secret-sentinel-3" }
      credentials(secrets)
      local_catalog

      check.run(printed)

      expect(printed.string).not_to include("secret-sentinel")
      expect(printed.string).to include("✓ stripe.secret_key")
    end

    it "marks credential rows unknown when the key is missing" do
      credentials
      @root.join("config/credentials/production.key").delete

      check.run(printed)

      expect(check.refusals.grep(/No key opens/).size).to eq(1)
      expect(printed.string).to match(/smtp.user_name\s+credentials\s+unknown/)
      expect(printed.string).not_to include("✗ smtp")
      expect(check.refusals.size).to eq(1)
    end

    it "reports a broken local catalog as one refusal" do
      credentials
      local_catalog("inputs" => { "stripe.secret_key" => { "bogus" => 1 } })

      expect(check.refusals.grep(/required_production_config.local.yml/).size).to eq(1)
    end

    it "refuses once when the catalog file is missing" do
      credentials
      @root.join("config/required_production_config.yml").delete

      expect(check.refusals.grep(/required_production_config.yml/).size).to eq(1)
    end

    it "judges a staging destination by staging's env and credentials" do
      credentials({}, name: "production")
      write("config/deploy.staging.yml", { "env" => { "clear" => { "RAILS_CREDENTIALS_ENV" => "staging" } } }.to_yaml)
      secrets(template.join(".kamal/secrets.staging").read, name: "secrets.staging")
      credentials(ready_credentials.merge("stripe" => { "secret_key" => "sk_live_real" }), name: "staging")
      local_catalog

      expect(check("staging").refusals).to be_empty
      expect(check.refusals).not_to be_empty
    end

    it "doesn't double-report inputs a RequiredProductionConfig rule owns" do
      deploy(env: ready_env.except("RAILS_HOST"))
      credentials

      expect(check.refusals.grep(/RAILS_HOST/).size).to eq(1)
    end

    describe "rows that agree with the refusals" do
      def problem_rows = printed.string.lines.grep(/\A  [✗⚠] /).map { |row| row.split[1] }

      def run_with(env: ready_env, oauth: nil)
        deploy(env:)
        credentials(oauth ? ready_credentials.merge("oauth" => { "google" => oauth }) : ready_credentials)
        check.run(printed)
      end

      it "marks the hosts the boot guard refuses, one row per refusal" do
        run_with(env: ready_env.merge("RAILS_HOST" => "app.acme.example", "SMTP_ADDRESS" => "localhost"))

        expect(problem_rows).to contain_exactly("RAILS_HOST", "SMTP_ADDRESS")
        expect(printed.string).to include("⚠ RAILS_HOST", "⚠ SMTP_ADDRESS", "2 problems stop a deploy.")
      end

      it "marks a missing OAuth secret once its client id is set" do
        run_with(oauth: { "client_id" => "real-id" })

        expect(problem_rows).to eq([ "oauth.google.client_secret" ])
        expect(printed.string).to include("✗ oauth.google.client_secret", "1 problem stops a deploy.")
      end

      it "reads a placeholder OAuth secret without its client id as optional, and passes" do
        expect(run_with(oauth: { "client_secret" => "REPLACE_ME" })).to eq(0)

        expect(problem_rows).to be_empty
        expect(printed.string).to include("○ oauth.google.client_secret", "Nothing here stops a deploy.")
      end

      it "marks both backup destinations when the guard refuses the pair" do
        run_with(env: ready_env.merge("OBJECT_STORAGE_BUCKET" => "b", "OBJECT_STORAGE_REGION" => "auto"))

        expect(problem_rows).to include("BACKUP_PATH", "OBJECT_STORAGE_BUCKET")
        expect(check.refusals.grep(/both set/).size).to eq(1)
      end

      it "refuses a placeholder the boot guard lets through, such as an encryption key" do
        keys = ready_credentials["active_record_encryption"].merge("primary_key" => "<from bin/rails db:encryption:init>")
        deploy
        credentials(ready_credentials.merge("active_record_encryption" => keys))

        expect(check.run(printed)).to eq(1)
        expect(problem_rows).to eq([ "active_record_encryption.primary_key" ])
        expect(printed.string).to include("active_record_encryption.primary_key looks like a placeholder", "1 problem stops a deploy.")
      end
    end

    it "counts SECRET_KEY_BASE from the container env as secret_key_base, as Rails does" do
      deploy(secret: %w[RAILS_MASTER_KEY SECRET_KEY_BASE])
      secrets("#{template.join('.kamal/secrets').read}\nSECRET_KEY_BASE=env-sentinel\n")
      credentials(ready_credentials.except("secret_key_base"))

      expect(check.run(printed)).to eq(0)
      expect(printed.string).to match(/✓ secret_key_base\s+credentials\s+set$/)
      expect(printed.string).not_to include("env-sentinel")
    end

    it "prints set, not the value, for an input the deploy hands over under env.secret" do
      deploy(env: ready_env.except("RAILS_HOST"), secret: %w[RAILS_MASTER_KEY RAILS_HOST])
      secrets("#{template.join('.kamal/secrets').read}\nRAILS_HOST=secret-host.acme.test\n")
      credentials

      check.run(printed)

      expect(printed.string).to match(/✓ RAILS_HOST\s+deploy.yml env\s+set$/)
      expect(printed.string).not_to include("secret-host.acme.test")
    end
  end

  describe "bin/rails deploy:check" do
    before { RakeTasks.load_once }

    around do |example|
      inherited = ENV["DESTINATION"]
      ENV["DESTINATION"] = "staging"
      ENV["DEPLOY_CHECK_COMPACT"] = "1"
      example.run
    ensure
      ENV["DESTINATION"] = inherited
      ENV.delete("DEPLOY_CHECK_COMPACT")
    end

    it "checks the destination DESTINATION names, after booting the app, and exits with the check's status" do
      check = instance_double(described_class, run: 1)
      allow(described_class).to receive(:new).with(root: Rails.root, destination: "staging", compact: true).and_return(check)

      expect(Rake::Task["deploy:check"].prerequisites).to include("environment")
      expect { Rake::Task["deploy:check"].execute }.to raise_error(SystemExit) { |exit| expect(exit.status).to eq(1) }
    end
  end
end
