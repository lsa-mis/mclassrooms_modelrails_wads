# frozen_string_literal: true

# What the code reads from credentials and ENV, scanned from source text.
# Shared by the deployment guide spec and the production config parity spec.
module CodeReads
  GLOB = "{app,config,db,lib}/**/*.{rb,yml,erb,rake}"
  CREDENTIAL_DIG = /credentials\.dig\(([^)]*)\)/
  ENV_READ = /ENV(?:\.fetch)?[\[(]"([A-Z][A-Z0-9_]*)"/

  # Dotted paths; credentials.dig(:smtp, key) scans as "smtp".
  def self.credential_keys = credential_files.keys

  def self.env_names = env_files.keys

  # Each read mapped to the files that make it.
  def self.credential_files
    reads_matching(CREDENTIAL_DIG) do |args|
      args.split(/,\s*/).take_while { |arg| arg.start_with?(":") }.map { |arg| arg.delete_prefix(":") }.join(".")
    end
  end

  def self.env_files = reads_matching(ENV_READ) { |name| name }

  def self.reads_matching(pattern)
    Dir[Rails.root.join(GLOB)].each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |file, reads|
      File.read(file).scan(pattern).flatten.each do |match|
        name = yield(match)
        reads[name] |= [ Pathname(file).relative_path_from(Rails.root).to_s ]
      end
    end.sort.to_h
  end
  private_class_method :reads_matching
end
