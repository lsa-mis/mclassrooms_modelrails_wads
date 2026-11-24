# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/fnox-setup")

RSpec.describe FnoxSetup do
  let(:output) { StringIO.new }
  let(:production_key) { "fake-production-key-0001" }
  let(:staging_key) { "fake-staging-key-0002" }

  around do |example|
    Dir.mktmpdir do |dir|
      @tmp = Pathname.new(dir)
      %w[root home bin store].each { |name| @tmp.join(name).mkpath }
      root.join("config/credentials").mkpath
      example.run
    end
  end

  def root = @tmp.join("root")
  def home = @tmp.join("home")
  def identity = home.join(".config/fnox/age.txt")
  def fnox_toml = root.join("fnox.toml")
  def calls = @tmp.join("calls.log").exist? ? @tmp.join("calls.log").read : ""

  def stub(name, body)
    @tmp.join("bin", name).write("#!/bin/sh\n#{body}\n")
    @tmp.join("bin", name).chmod(0o755)
  end

  def install_tools
    log = @tmp.join("calls.log")
    store = @tmp.join("store")
    stub("age-keygen", <<~SH)
      echo "age-keygen $*" >> #{log}
      if [ "$1" = "-y" ]; then
        [ "$(cat "$2")" = "VALID-IDENTITY" ] || { echo "malformed" >&2; exit 1; }
        echo age1stubrecipient
      elif [ "$1" = "-o" ]; then
        echo VALID-IDENTITY > "$2"
        echo "Public key: age1stubrecipient" >&2
      fi
    SH
    stub("fnox", <<~SH)
      profile=default
      if [ "$1" = "--profile" ]; then profile=$2; shift 2; fi
      echo "fnox $*" >> #{log}
      case "$1" in
        set) for a in "$@"; do [ "$prev" = "--profile" ] && profile=$a; prev=$a; done
             cat > #{store}/$profile ;;
        get) [ -f #{store}/$profile ] && tr -d '\\n' < #{store}/$profile || exit 1 ;;
      esac
    SH
  end

  def existing_identity
    identity.dirname.mkpath
    identity.write("VALID-IDENTITY\n")
  end

  def keys(staging: false)
    root.join("config/credentials/production.key").write("#{production_key}\n")
    root.join("config/credentials/staging.key").write("#{staging_key}\n") if staging
  end

  def run_setup(dry_run: false, path: "#{@tmp.join('bin')}:/usr/bin:/bin", env: {})
    described_class.new(root: root.to_s, home: home.to_s, env: { "PATH" => path }.merge(env), output:, dry_run:).run
  end

  it "ends with what to commit and back up when run on its own" do
    install_tools
    keys
    existing_identity
    run_setup

    expect(output.string).to include("Commit fnox.toml")
  end

  it "treats an empty PRODUCTION_SETUP as unset, as bin/mail-setup does" do
    install_tools
    keys
    existing_identity
    run_setup(env: { "PRODUCTION_SETUP" => "" })

    expect(output.string).to include("Commit fnox.toml")
  end

  it "leaves the ending to bin/production-setup when run inside it" do
    install_tools
    keys
    existing_identity
    expect(run_setup(env: { "PRODUCTION_SETUP" => "1" })).to eq(0)

    expect(output.string).not_to include("Commit fnox.toml")
    expect(output.string).to include("Stored production's RAILS_MASTER_KEY in fnox")
  end

  it "refuses without production.key and points at bin/mail-setup" do
    install_tools

    expect(run_setup).to eq(1)
    expect(output.string).to include("bin/mail-setup")
  end

  it "refuses when fnox or age-keygen isn't installed and points at mise install" do
    keys

    expect(run_setup(path: "/usr/bin:/bin")).to eq(1)
    expect(output.string).to include("mise install")
  end

  it "reuses an existing identity and never rewrites it" do
    install_tools
    keys
    existing_identity
    before = [ identity.read, identity.mtime ]

    expect(run_setup).to eq(0)
    expect([ identity.read, identity.mtime ]).to eq(before)
    expect(calls).to include("age-keygen -y #{identity}")
    expect(calls).not_to include("age-keygen -o")
  end

  it "stops without touching an identity age-keygen can't read" do
    install_tools
    keys
    identity.dirname.mkpath
    identity.write("NOT-AN-IDENTITY\n")

    expect(run_setup).to eq(1)
    expect(identity.read).to eq("NOT-AN-IDENTITY\n")
    expect(fnox_toml).not_to exist
  end

  it "creates an identity with mode 0600 when there is none" do
    install_tools
    keys

    expect(run_setup).to eq(0)
    expect(identity.read).to eq("VALID-IDENTITY\n")
    expect(identity.stat.mode & 0o777).to eq(0o600)
    expect(output.string).to include("password manager")
  end

  it "names the age file by its path, never as an identity, which is the app's own word" do
    install_tools
    keys
    expect(run_setup(dry_run: true)).to eq(0)
    expect(run_setup).to eq(0)
    expect(run_setup).to eq(0)

    expect(output.string).to include("Would create ~/.config/fnox/age.txt", "Created ~/.config/fnox/age.txt",
                                     "Using ~/.config/fnox/age.txt")
    expect(output.string).not_to match(/identity/i)
  end

  it "writes fnox.toml with both providers holding the recipient" do
    install_tools
    keys
    existing_identity

    run_setup

    expect(fnox_toml.read).to include("[providers.age-production]", "[providers.age-staging]")
    expect(fnox_toml.read.scan("age1stubrecipient").size).to eq(2)
  end

  it "leaves a fnox.toml it already completed alone on a second run" do
    install_tools
    keys
    existing_identity
    run_setup
    before = fnox_toml.read
    File.write(@tmp.join("calls.log"), "")

    expect(run_setup).to eq(0)
    expect(fnox_toml.read).to eq(before)
    expect(calls).not_to include("fnox set")
  end

  it "never rewrites a fnox.toml it doesn't recognize, and prints the block to add" do
    install_tools
    keys
    existing_identity
    fnox_toml.write("[providers.vault]\ntype = \"1password\"\n")

    expect(run_setup).to eq(1)
    expect(fnox_toml.read).to eq("[providers.vault]\ntype = \"1password\"\n")
    expect(output.string).to include("[providers.age-production]", "age1stubrecipient")
  end

  it "stores production's key by stdin, never on the command line" do
    install_tools
    keys
    existing_identity

    run_setup

    expect(calls).to include("fnox set RAILS_MASTER_KEY --provider age-production")
    expect(calls).not_to include(production_key)
    expect(@tmp.join("store/default").read.strip).to eq(production_key)
  end

  it "stores staging's key under the staging profile only when staging.key exists" do
    install_tools
    keys
    existing_identity
    run_setup
    expect(calls).not_to include("age-staging")

    keys(staging: true)
    run_setup

    expect(calls).to include("fnox set RAILS_MASTER_KEY --provider age-staging --profile staging")
    expect(@tmp.join("store/staging").read.strip).to eq(staging_key)
  end

  it "never prints a key or the identity" do
    install_tools
    keys(staging: true)

    run_setup

    expect(output.string).not_to include(production_key, staging_key, "VALID-IDENTITY")
  end

  it "stops when fnox gives back a different value, printing neither" do
    install_tools
    keys
    existing_identity
    stub("fnox", 'case "$*" in *get*) echo something-else ;; esac')

    expect(run_setup).to eq(1)
    expect(output.string).to include("fnox check --all")
    expect(output.string).not_to include(production_key, "something-else")
  end

  it "changes nothing under --dry-run" do
    install_tools
    keys

    expect(run_setup(dry_run: true)).to eq(0)
    expect(identity).not_to exist
    expect(fnox_toml).not_to exist
    expect(calls).not_to include("fnox set")
  end

  it "changes nothing under --dry-run when fnox.toml exists but the identity doesn't yet" do
    install_tools
    keys
    fnox_toml.write("[providers.vault]\ntype = \"1password\"\n")

    expect(run_setup(dry_run: true)).to eq(0)
    expect(fnox_toml.read).to eq("[providers.vault]\ntype = \"1password\"\n")
    expect(identity).not_to exist
  end
end
