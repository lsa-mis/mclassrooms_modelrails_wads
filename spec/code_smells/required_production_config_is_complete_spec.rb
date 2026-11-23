# frozen_string_literal: true

require "rails_helper"

# The catalog describes every input production needs. Without this fence it
# drifts: code starts reading a credential or ENV variable nobody described.
RSpec.describe "The production config catalog" do
  # Read, but not through a literal ENV["NAME"] the scan can see.
  let(:unscannable) do
    {
      "secret_key_base" => "Rails reads it itself",
      "SMTP_ADDRESS" => "read through MailDelivery's injected env hash",
      "SMTP_PORT" => "read through MailDelivery's injected env hash",
      "BACKUP_PATH" => "read through DatabaseBackup's injected env hash"
    }
  end
  let(:catalog) { RequiredProductionConfigCatalog.load(root: Rails.root) }
  let(:keys) { catalog.entries.map(&:key) }
  let(:fork_file) { RequiredProductionConfigCatalog::LOCAL_PATH }

  def covered?(read) = catalog.exclusions.keys.any? { |name| name == read || read.start_with?("#{name}.") } || keys.any? { |key| key == read || key.start_with?("#{read}.") }

  def uncovered(reads) = reads.reject { |read, _files| covered?(read) }

  def message(kind, missing)
    lines = missing.map { |read, files| "  #{read} (read in #{files.join(", ")})" }
    "#{kind} the code reads that the catalog neither describes nor excludes:\n#{lines.join("\n")}\n" \
      "Describe each in config/required_production_config.yml, or in #{fork_file} for a fork, or exclude it there with a reason."
  end

  it "describes or excludes every credential the code reads" do
    missing = uncovered(CodeReads.credential_files)

    expect(missing).to be_empty, message("Credentials", missing)
  end

  it "describes or excludes every ENV variable the code reads" do
    missing = uncovered(CodeReads.env_files)

    expect(missing).to be_empty, message("ENV variables", missing)
  end

  it "scans rake tasks too" do
    expect(CodeReads.env_files).to include("DEPLOY_CHECK_COMPACT" => [ "lib/tasks/deploy.rake" ])
  end

  it "has no entry for a credential or env input nothing reads" do
    reads = CodeReads.credential_keys + CodeReads.env_names
    checked = catalog.entries.reject { |entry| %w[kamal_secret dns dashboard].include?(entry.home) || unscannable.key?(entry.key) }
    unread = checked.reject { |entry| reads.any? { |read| entry.key == read || entry.key.start_with?("#{read}.") } }

    expect(unread.map(&:key)).to be_empty,
      "Catalog entries nothing reads: #{unread.map(&:key).join(", ")}. Remove them from the catalog (#{fork_file} for a fork's own)."
  end
end
