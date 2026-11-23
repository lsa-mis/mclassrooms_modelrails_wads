require "rails_helper"
require "open3"
require "tmpdir"

# Kamal runs .kamal/hooks/pre-build before every build; here a fake bin/rails stands in for the check.
RSpec.describe ".kamal/hooks/pre-build" do
  let(:hook) { Rails.root.join(".kamal/hooks/pre-build") }

  around do |example|
    Dir.mktmpdir do |dir|
      @app = Pathname.new(dir)
      example.run
    end
  end

  def app_whose_check_exits(code)
    @app.join(".kamal/hooks").mkpath
    @app.join("bin").mkpath
    FileUtils.cp(hook, @app.join(".kamal/hooks/pre-build"))
    @app.join(".kamal/hooks/pre-build").chmod(0o755)
    @app.join("bin/rails").write("#!/bin/sh\necho \"rails $* DESTINATION=$DESTINATION RAILS_ENV=$RAILS_ENV COMPACT=$DEPLOY_CHECK_COMPACT\"\nexit #{code}\n")
    @app.join("bin/rails").chmod(0o755)
  end

  # Unset unless an example sets it, so the runner's own environment can't reach the hook.
  def run_hook(env = {})
    hermetic = { "KAMAL_DESTINATION" => nil, "DESTINATION" => nil, "RAILS_ENV" => nil }
    Open3.capture2e(hermetic.merge(env), @app.join(".kamal/hooks/pre-build").to_s, chdir: "/")
  end

  it "is executable, so Kamal runs it" do
    expect(hook).to be_executable
  end

  it "runs the deploy check for the destination Kamal is building" do
    app_whose_check_exits(0)

    output, status = run_hook("KAMAL_DESTINATION" => "staging")

    expect(status).to be_success
    expect(output).to include("rails deploy:check DESTINATION=staging ")
  end

  # CI's deploy job exports DESTINATION=production, which names no deploy file.
  it "takes the destination from Kamal, not from the shell" do
    app_whose_check_exits(0)

    output, = run_hook("DESTINATION" => "production")

    expect(output).to include("rails deploy:check DESTINATION= ")
  end

  it "checks from development, whatever RAILS_ENV the shell exports" do
    app_whose_check_exits(0)

    output, = run_hook("RAILS_ENV" => "production")

    expect(output).to include("RAILS_ENV=development")
  end

  it "asks for the compact form, which prints problems only" do
    app_whose_check_exits(0)

    output, = run_hook

    expect(output).to include("COMPACT=1")
  end

  it "shows the check's warnings on every deploy, not only when it fails" do
    require "kamal"
    @app.join("config").mkpath
    FileUtils.cp(Rails.root.join("config/deploy.yml"), @app.join("config/deploy.yml"))
    FileUtils.cp(Rails.root.join(".tool-versions"), @app)
    config = Dir.chdir(@app) { Kamal::Configuration.create_from(config_file: Pathname("config/deploy.yml")) }

    expect(config.hooks_output_for("pre-build")).to eq(:verbose)
  end

  it "stops the build when the check refuses" do
    app_whose_check_exits(1)

    _, status = run_hook

    expect(status).not_to be_success
  end
end
