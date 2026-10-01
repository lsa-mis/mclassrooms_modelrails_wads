# frozen_string_literal: true

require "rails_helper"

# `.kamal/secrets` is TRACKED. Kamal reads it (and its `-common` /
# `.<destination>` siblings) with Dotenv.parse plus inline command
# substitution, so every value can and must be a reference resolved at deploy
# time — `$VAR` from the environment, or `$(...)` from a password manager.
#
# A literal here is a credential committed to git, and this is a fork template:
# whatever shape the file ships in is the shape every fork copies. The docs
# used to instruct exactly that (#1080), which is how this guard came to exist.
#
# Failure output names KEYS and line numbers only — never values. A guard that
# prints the secret it caught has leaked it into CI logs.
RSpec.describe "Kamal secrets files hold references, never literals" do
  # Every secrets file Kamal would read: Kamal::Secrets#secrets_filenames is
  # ["<path>-common", "<path>[.<destination>]"], default path ".kamal/secrets".
  let(:secrets_files) { Dir[Rails.root.join(".kamal/secrets*")].sort }

  # CleanGitEnv::HASH: a spawn that inherits GIT_DIR answers for whatever
  # repository that points at — from a git hook, not this one (#789, #1056).
  def tracked?(path)
    system(CleanGitEnv::HASH, "git", "ls-files", "--error-unmatch", path.to_s,
           out: File::NULL, err: File::NULL)
  end

  it "has at least one secrets file to check" do
    expect(secrets_files).not_to be_empty,
      "no .kamal/secrets* files found — has the Kamal config moved?"
  end

  it "assigns every key a $-reference, never an inline value" do
    scanned = 0
    violations = secrets_files.flat_map do |file|
      next [] unless tracked?(file)

      scanned += 1

      relative = file.delete_prefix("#{Rails.root}/")
      File.readlines(file).each_with_index.filter_map do |line, index|
        next if line.strip.empty? || line.strip.start_with?("#")

        key, value = line.chomp.split("=", 2)
        next if value.nil? || value.strip.empty?
        next if value.strip.start_with?("$")

        # Deliberately reports the KEY, never the VALUE.
        "#{relative}:#{index + 1} — #{key.strip} is assigned a literal"
      end
    end

    # POSITIVE CONTROL: a failing `git ls-files` would empty the scan (#1056).
    expect(scanned).to be_positive,
      "no Kamal secrets file was actually scanned: #{secrets_files.size} file(s) found, all skipped " \
      "as untracked. If `git ls-files` is failing, this guard is not checking anything."

    expect(violations).to be_empty, <<~MESSAGE
      Tracked Kamal secrets files must assign references, not literals:

      #{violations.join("\n")}

      Use `$VAR` (resolved from the deploy-time environment) or `$(...)`
      (resolved by a password-manager CLI). See app/docs/developer/deployment.
    MESSAGE
  end
end
