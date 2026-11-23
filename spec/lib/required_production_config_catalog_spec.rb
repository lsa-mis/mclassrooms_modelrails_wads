require "rails_helper"
require "tmpdir"
require "fileutils"

RSpec.describe RequiredProductionConfigCatalog do
  let(:header) { "# Describes what production needs. Values go in credentials, deploy.yml or fnox; never here." }
  let(:local_entry) do
    {
      "home" => "credentials", "required" => "optional", "secret" => true,
      "purpose" => "Charges cards", "where" => "Stripe dashboard", "set_with" => "credentials:edit",
      "step" => 4, "example" => "<from Stripe → Developers → API keys>"
    }
  end

  def with_fork_root(local: nil, raw_local: nil)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      FileUtils.cp(Rails.root.join("config/required_production_config.yml"), File.join(dir, "config"))
      path = File.join(dir, "config/required_production_config.local.yml")
      File.write(path, raw_local || { "inputs" => local }.to_yaml) if local || raw_local
      yield Pathname(dir)
    end
  end

  it "loads the template entries" do
    catalog = described_class.load(root: Rails.root)

    expect(catalog.entries.map(&:key)).to include("RAILS_HOST", "smtp.password", "RAILS_MASTER_KEY")
    expect(catalog.entries.map(&:source).uniq).to eq([ :template ])
    expect(catalog.exclusions.keys).to include("WEB_CONCURRENCY", "aws")
  end

  it "calls what the encryption keys protect personal data, as the quickstart and bin/encryption-setup do" do
    purposes = described_class.load(root: Rails.root).entries.select { |entry| entry.key.start_with?("active_record_encryption.") }.map(&:purpose)

    expect(purposes.size).to eq(3)
    expect(purposes).to all(include("personal data"))
  end

  it "appends a fork's local entries" do
    with_fork_root(local: { "stripe.secret_key" => local_entry }) do |root|
      last = described_class.load(root: root).entries.last

      expect(last.key).to eq("stripe.secret_key")
      expect(last.source).to eq(:local)
    end
  end

  it "rejects an unknown field, naming file and key" do
    with_fork_root(local: { "stripe.secret_key" => local_entry.merge("value" => "sk_live_1") }) do |root|
      expect { described_class.load(root: root) }
        .to raise_error(described_class::Invalid, /required_production_config\.local\.yml.*stripe\.secret_key.*value/)
    end
  end

  it "rejects a secret credential whose example isn't a placeholder" do
    with_fork_root(local: { "stripe.secret_key" => local_entry.merge("example" => "sk_live_51H") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /stripe\.secret_key/)
    end
  end

  it "rejects a non-secret credential whose example isn't a placeholder" do
    with_fork_root(local: { "stripe.account" => local_entry.merge("secret" => false, "example" => "acct_123") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /stripe\.account/)
    end
  end

  it "rejects a local entry that redefines a template key" do
    with_fork_root(local: { "RAILS_HOST" => local_entry.merge("home" => "env") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /RAILS_HOST/)
    end
  end

  it "rejects owner_rule in a local entry" do
    with_fork_root(local: { "stripe.secret_key" => local_entry.merge("owner_rule" => "host") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /stripe\.secret_key.*owner_rule/)
    end
  end

  it "rejects a value outside the schema's vocabulary" do
    with_fork_root(local: { "stripe.secret_key" => local_entry.merge("home" => "vault") }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /stripe\.secret_key.*home/)
    end
  end

  it "accepts the conditional forms of required" do
    conditional = local_entry.merge("required" => { "when_env_set" => "STRIPE_ON" })

    with_fork_root(local: { "stripe.secret_key" => conditional }) do |root|
      expect(described_class.load(root: root).entries.last.required).to eq({ "when_env_set" => "STRIPE_ON" })
    end
  end

  it "accepts a credential as the condition, and rejects one that isn't a dotted path" do
    gated = local_entry.merge("required" => { "when_credential_set" => "stripe.account_id" })

    with_fork_root(local: { "stripe.secret_key" => gated }) do |root|
      expect(described_class.load(root: root).entries.last.required).to eq({ "when_credential_set" => "stripe.account_id" })
    end
    with_fork_root(local: { "stripe.secret_key" => gated.merge("required" => { "when_credential_set" => "STRIPE" }) }) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /stripe\.secret_key.*required/)
    end
  end

  it "rejects a key that isn't text, naming the file" do
    with_fork_root(raw_local: { "inputs" => { 42 => local_entry.merge("home" => "dns") } }.to_yaml) do |root|
      expect { described_class.load(root: root) }.to raise_error(described_class::Invalid, /required_production_config\.local\.yml: 42/)
    end
  end

  it "reports a YAML syntax error as Invalid" do
    with_fork_root(raw_local: "inputs: [unclosed") do |root|
      expect { described_class.load(root: root) }
        .to raise_error(described_class::Invalid, /required_production_config\.local\.yml/)
    end
  end

  it "merges exclusions from both files" do
    with_fork_root(raw_local: { "exclusions" => { "STRIPE_DEBUG" => "Dev only" } }.to_yaml) do |root|
      exclusions = described_class.load(root: root).exclusions

      expect(exclusions).to include("STRIPE_DEBUG" => "Dev only", "WEB_CONCURRENCY" => a_kind_of(String))
    end
  end

  it "puts each input in the quickstart step that handles it" do
    steps = described_class.load(root: Rails.root).entries.group_by { |entry| entry.home }
                           .transform_values { |entries| entries.map(&:step).uniq.sort }

    expect(steps.fetch("credentials")).to eq([ 4 ])
    expect(steps.fetch("kamal_secret")).to eq([ 4 ])
    expect(steps.fetch("env")).to eq([ 4, 6 ])
  end

  it "names where each env input is set, and says something specific about its value" do
    env = described_class.load(root: Rails.root).entries.select { |entry| entry.home == "env" }

    expect(env.map(&:set_with).uniq).to eq([ "config/deploy.yml → env.clear" ])
    expect(env.map(&:where).uniq.size).to eq(env.size)
  end

  it "starts the template file with the header line" do
    expect(File.foreach(Rails.root.join("config/required_production_config.yml")).first.chomp).to eq(header)
  end

  describe "Entry#status" do
    def entry(home: "env", key: "HOST", required: "always", example: nil)
      described_class::Entry.new(key: key, home: home, required: required, secret: false, purpose: "p", where: "w",
                                 set_with: "s", regenerable: nil, step: 4, example: example, owner_rule: nil,
                                 source: :template)
    end

    def status(entry, env: {}, credentials: {}, preset: nil, key_resolves: false)
      entry.status(env: env, credentials: credentials, preset: preset, key_resolves: key_resolves)
    end

    let(:smtp_password) { entry(home: "credentials", key: "smtp.password", example: "<from Postmark>") }

    it "is set when a required env value is present" do
      expect(status(entry, env: { "HOST" => "example.com" })).to eq(:set)
    end

    it "is missing when a required env value is blank" do
      expect(status(entry, env: { "HOST" => " " })).to eq(:missing)
    end

    it "is optional_unset when an optional env value is blank" do
      expect(status(entry(required: "optional"))).to eq(:optional_unset)
    end

    it "follows when_env_set on the other variable" do
      conditional = entry(key: "BUCKET_REGION", required: { "when_env_set" => "OBJECT_STORAGE_BUCKET" })

      expect(status(conditional)).to eq(:optional_unset)
      expect(status(conditional, env: { "OBJECT_STORAGE_BUCKET" => "b" })).to eq(:missing)
    end

    it "follows when_env_unset on the other variable" do
      conditional = entry(key: "BACKUP_PATH", required: { "when_env_unset" => "OBJECT_STORAGE_BUCKET" })

      expect(status(conditional)).to eq(:missing)
      expect(status(conditional, env: { "OBJECT_STORAGE_BUCKET" => "b" })).to eq(:optional_unset)
    end

    it "follows the preset for when_preset" do
      shared = entry(required: { "when_preset" => "shared" })

      expect(status(shared, preset: "shared")).to eq(:missing)
      expect(status(shared, preset: nil)).to eq(:optional_unset)
    end

    it "calls a credential equal to its example, or REPLACE_ME, a placeholder" do
      expect(status(smtp_password, credentials: { smtp: { password: "<from Postmark>" } })).to eq(:placeholder)
      expect(status(smtp_password, credentials: { smtp: { password: "REPLACE_ME" } })).to eq(:placeholder)
    end

    it "calls an optional credential that is present and a placeholder a placeholder" do
      optional = entry(home: "credentials", key: "smtp.password", required: "optional", example: "<from Postmark>")

      expect(status(optional, credentials: { smtp: { password: "REPLACE_ME" } })).to eq(:placeholder)
    end

    it "is set for a real credential" do
      expect(status(smtp_password, credentials: { smtp: { password: "s3cret" } })).to eq(:set)
    end

    it "is unknown for credentials that could not be opened" do
      expect(status(smtp_password, credentials: nil)).to eq(:unknown)
    end

    it "is uncheckable for dns and dashboard entries" do
      expect(status(entry(home: "dns", key: "MX"))).to eq(:uncheckable)
      expect(status(entry(home: "dashboard", key: "ZONE"))).to eq(:uncheckable)
    end

    it "follows key_resolves for a kamal_secret" do
      secret = entry(home: "kamal_secret", key: "KAMAL_REGISTRY_PASSWORD")

      expect(status(secret, key_resolves: true)).to eq(:set)
      expect(status(secret, key_resolves: false)).to eq(:missing)
    end

    it "is missing, without raising, when an intermediate credential is not a mapping" do
      expect(status(smtp_password, credentials: { smtp: "x" })).to eq(:missing)
      expect(status(smtp_password, credentials: { smtp: [ 1, 2 ] })).to eq(:missing)
    end

    describe "a secret its client id switches on" do
      let(:secret) { entry(home: "credentials", key: "oauth.google.client_secret", example: "<from Google>",
                           required: { "when_credential_set" => "oauth.google.client_id" }) }

      it "is missing once the id is set, and optional without it" do
        expect(status(secret, credentials: { oauth: { google: { client_id: "real-id" } } })).to eq(:missing)
        expect(status(secret, credentials: {})).to eq(:optional_unset)
      end

      it "reads optional, not a placeholder, while the id is absent" do
        expect(status(secret, credentials: { oauth: { google: { client_secret: "REPLACE_ME" } } })).to eq(:optional_unset)
        expect(status(secret, credentials: { oauth: { google: { client_id: "real-id", client_secret: "REPLACE_ME" } } })).to eq(:placeholder)
      end

      it "doesn't raise when oauth is not a mapping" do
        expect(status(secret, credentials: { oauth: "x" })).to eq(:optional_unset)
      end
    end

    it "is set for a numeric credential" do
      port = entry(home: "credentials", key: "smtp.port", example: "<port>")

      expect(status(port, credentials: { smtp: { port: 587 } })).to eq(:set)
    end
  end
end
