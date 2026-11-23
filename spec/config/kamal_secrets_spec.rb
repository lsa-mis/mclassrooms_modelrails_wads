# frozen_string_literal: true

require "rails_helper"
require "kamal"

RSpec.describe ".kamal/secrets" do
  around do |example|
    original = ENV.fetch("RAILS_MASTER_KEY", nil)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".kamal"))
      FileUtils.cp(Dir[Rails.root.join(".kamal/secrets*")], File.join(dir, ".kamal"))
      FileUtils.mkdir_p(File.join(dir, "config/credentials"))
      File.write(File.join(dir, "config/credentials/production.key"), "key-from-file\n")
      File.write(File.join(dir, "config/credentials/staging.key"), "staging-key-from-file\n")
      Dir.chdir(dir) { example.run }
    end
  ensure
    original.nil? ? ENV.delete("RAILS_MASTER_KEY") : ENV["RAILS_MASTER_KEY"] = original
  end

  def master_key = Kamal::Secrets.new["RAILS_MASTER_KEY"]

  it "takes RAILS_MASTER_KEY from the deploy's environment first" do
    ENV["RAILS_MASTER_KEY"] = "key-from-env"

    expect(master_key).to eq("key-from-env")
  end

  it "falls back to the production key file when the environment has none" do
    ENV.delete("RAILS_MASTER_KEY")

    expect(master_key).to eq("key-from-file")
  end

  it "falls back to the key file when the environment's value is blank" do
    ENV["RAILS_MASTER_KEY"] = ""

    expect(master_key).to eq("key-from-file")
  end

  context "with fnox" do
    around do |example|
      path = ENV.fetch("PATH")
      FileUtils.mkdir_p("stub-bin")
      ENV["PATH"] = "#{File.expand_path('stub-bin')}:#{path}"
      example.run
    ensure
      ENV["PATH"] = path
    end

    def install_fnox(script)
      File.write("stub-bin/fnox", "#!/bin/sh\n#{script}\n")
      File.chmod(0o755, "stub-bin/fnox")
    end

    it "takes RAILS_MASTER_KEY from fnox when the environment has none" do
      ENV.delete("RAILS_MASTER_KEY")
      install_fnox('[ "$*" = "get RAILS_MASTER_KEY" ] && echo key-from-fnox')

      expect(master_key).to eq("key-from-fnox")
    end

    it "still prefers the deploy's environment over fnox" do
      ENV["RAILS_MASTER_KEY"] = "key-from-env"
      install_fnox("echo key-from-fnox")

      expect(master_key).to eq("key-from-env")
    end

    it "falls back to the key file when fnox has no value for it" do
      ENV.delete("RAILS_MASTER_KEY")
      install_fnox("echo 'Error: secret not found' >&2; exit 1")

      expect(master_key).to eq("key-from-file")
    end

    context "for the staging destination" do
      def master_key = Kamal::Secrets.new(destination: "staging")["RAILS_MASTER_KEY"]

      it "takes RAILS_MASTER_KEY from fnox's staging profile when the environment has none" do
        ENV.delete("RAILS_MASTER_KEY")
        install_fnox('[ "$*" = "--profile staging get RAILS_MASTER_KEY" ] && echo key-from-fnox-staging')

        expect(master_key).to eq("key-from-fnox-staging")
      end

      it "never takes production's fnox value for staging" do
        ENV.delete("RAILS_MASTER_KEY")
        install_fnox('[ "$*" = "get RAILS_MASTER_KEY" ] && echo key-from-fnox-production')

        expect(master_key).to eq("staging-key-from-file")
      end
    end
  end

  it "falls back to the key file when fnox isn't installed" do
    ENV.delete("RAILS_MASTER_KEY")
    path = ENV.fetch("PATH")
    ENV["PATH"] = path.split(File::PATH_SEPARATOR).reject { |dir| File.executable?(File.join(dir, "fnox")) }.join(File::PATH_SEPARATOR)

    expect(master_key).to eq("key-from-file")
  ensure
    ENV["PATH"] = path
  end

  context "for the staging destination" do
    def master_key = Kamal::Secrets.new(destination: "staging")["RAILS_MASTER_KEY"]

    it "takes RAILS_MASTER_KEY from the deploy's environment first" do
      ENV["RAILS_MASTER_KEY"] = "key-from-env"

      expect(master_key).to eq("key-from-env")
    end

    it "falls back to the staging key file, never production's" do
      ENV.delete("RAILS_MASTER_KEY")

      expect(master_key).to eq("staging-key-from-file")
    end
  end
end
