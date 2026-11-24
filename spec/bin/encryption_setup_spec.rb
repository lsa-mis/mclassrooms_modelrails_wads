# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/encryption-setup")

RSpec.describe EncryptionSetup do
  let(:output) { StringIO.new }
  let(:master_key) { SecureRandom.hex(16) }

  around do |example|
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      @root.join("config/credentials").mkpath
      example.run
    end
  end

  def credentials
    ActiveSupport::EncryptedFile.new(content_path: @root.join("config/credentials/production.yml.enc"),
                                     key_path: @root.join("config/credentials/production.key"),
                                     env_key: "UNUSED_IN_SPEC", raise_if_missing_key: true)
  end

  def credentials_with(text)
    @root.join("config/credentials/production.key").write(master_key)
    credentials.write(text)
  end

  def encrypted = @root.join("config/credentials/production.yml.enc")
  def stored = YAML.safe_load(credentials.read)
  def run_setup(env: {}, dry_run: false) = described_class.new(root: @root.to_s, env:, output:, dry_run:).run

  it "writes all three keys when they're missing, keeping the rest of the file" do
    credentials_with("# comment kept\nsecret_key_base: abc\n")

    expect(run_setup).to eq(0)
    keys = stored.fetch("active_record_encryption")
    expect(keys.keys).to eq(%w[primary_key deterministic_key key_derivation_salt])
    expect(keys.values).to all(match(/\A[A-Za-z0-9]{32}\z/))
    expect(stored.fetch("secret_key_base")).to eq("abc")
    expect(credentials.read).to start_with("# comment kept\n")
  end

  it "leaves existing keys alone" do
    credentials_with("active_record_encryption:\n  primary_key: a\n  deterministic_key: b\n  key_derivation_salt: c\n")
    before = encrypted.binread

    expect(run_setup).to eq(0)
    expect(encrypted.binread).to eq(before)
    expect(output.string).to include("already")
  end

  it "refuses to complete a partial section" do
    credentials_with("active_record_encryption:\n  primary_key: a\n")
    before = encrypted.binread

    expect(run_setup).to eq(1)
    expect(encrypted.binread).to eq(before)
    expect(output.string).to include("what-production-credentials-hold")
  end

  it "leaves what to commit to bin/production-setup's summary when it runs inside it" do
    credentials_with("secret_key_base: abc\n")

    expect(run_setup(env: { "PRODUCTION_SETUP" => "1" })).to eq(0)
    expect(output.string).to include("Added the personal-data encryption keys")
    expect(output.string).not_to include("Commit")
  end

  it "says what to commit when it runs on its own" do
    credentials_with("secret_key_base: abc\n")

    run_setup

    expect(output.string).to include("Commit it; production.key stays out of git.")
  end

  it "never prints a key" do
    credentials_with("secret_key_base: abc\n")

    run_setup

    stored.fetch("active_record_encryption").each_value { |key| expect(output.string).not_to include(key) }
  end

  it "refuses without production credentials and points at bin/mail-setup" do
    expect(run_setup).to eq(1)
    expect(output.string).to include("bin/mail-setup")
  end

  it "refuses when RAILS_MASTER_KEY in the shell can't read the file" do
    credentials_with("secret_key_base: abc\n")

    expect(run_setup(env: { "RAILS_MASTER_KEY" => SecureRandom.hex(16) })).to eq(1)
    expect(output.string).to include("unset RAILS_MASTER_KEY")
    expect(stored).not_to have_key("active_record_encryption")
  end

  it "changes nothing under --dry-run" do
    credentials_with("secret_key_base: abc\n")
    before = encrypted.binread

    expect(run_setup(dry_run: true)).to eq(0)
    expect(encrypted.binread).to eq(before)
  end
end
