require "rails_helper"
require "open3"
require "tmpdir"

# Runs the real bin/setup in a throwaway fork clone; bundle and bin/rails are fakes that log their calls.
RSpec.describe "bin/setup" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = Pathname.new(dir)
      example.run
    end
  end

  let(:app) { @dir.join("my_app") }
  let(:calls) { @dir.join("calls.log") }
  let(:template_url) { "git@github.com:someone/modelrails_base.git" }

  def git(*args) = system(CleanGitEnv::HASH, "git", "-C", app.to_s, *args, exception: true)
  def git_value(*args) = IO.popen(CleanGitEnv::HASH, [ "git", "-C", app.to_s, *args ], err: File::NULL, &:read).strip

  def fake(path, logged_as)
    path.dirname.mkpath
    path.write("#!/bin/sh\necho \"#{logged_as} $*\" >> \"#{calls}\"\n")
    path.chmod(0o755)
  end

  def clone_with(fork_yml)
    app.join("lib").mkpath
    fake(app.join("bin/rails"), "rails")
    fake(@dir.join("path/bundle"), "bundle")
    FileUtils.cp(Rails.root.join("bin/setup"), app.join("bin/setup"))
    %w[clean_git_env.rb fork_config.rb].each { |file| FileUtils.cp(Rails.root.join("lib", file), app.join("lib", file)) }
    app.join(".fork.yml").write(fork_yml) if fork_yml
    git("init", "-q")
  end

  def run_setup
    env = CleanGitEnv::HASH.merge("PATH" => "#{@dir.join('path')}:#{ENV.fetch('PATH')}")
    Open3.capture2e(env, RbConfig.ruby, app.join("bin/setup").to_s, "--skip-server")
  end

  def logged = calls.exist? ? calls.read : ""

  context "in a fork's clone" do
    before { clone_with("name: my_app\npreset: shared\ntemplate_url: #{template_url}\n") }

    it "adds the template as an upstream it can't push to" do
      run_setup

      expect(git_value("remote", "get-url", "upstream")).to eq(template_url)
      expect(git_value("remote", "get-url", "--push", "upstream")).to eq("DISABLED")
    end

    it "turns on the merge driver that keeps fork-owned files the fork's" do
      run_setup

      expect(git_value("config", "merge.ours.driver")).to eq("true")
    end

    it "writes the recorded preset, and the shared preset's slug, to .env" do
      run_setup

      expect(app.join(".env").read).to include("WORKSPACE_ON_SIGNUP=shared\n", "TENANCY_SHARED_WORKSPACE_SLUG=my_app\n")
    end

    it "keeps a preset .env already sets, and the rest of the file" do
      app.join(".env").write("SECRET_KEY=keep-me\nWORKSPACE_ON_SIGNUP=personal\n")

      run_setup

      expect(app.join(".env").read).to eq("SECRET_KEY=keep-me\nWORKSPACE_ON_SIGNUP=personal\n")
    end
  end

  it "refuses a preset the app would refuse to boot on" do
    clone_with("name: my_app\npreset: solo\n")

    output, status = run_setup

    expect(status).not_to be_success
    expect(output).to include('unknown preset "solo"')
  end

  it "names the file when .fork.yml isn't valid YAML" do
    clone_with("name: [unclosed\n")

    output, status = run_setup

    expect(status).not_to be_success
    expect(output).to include("bin/setup: .fork.yml is not valid YAML")
  end

  it "installs the git hooks and prepares the database in any clone" do
    clone_with(nil)

    run_setup

    expect(logged).to include("bundle exec lefthook install", "rails db:prepare")
  end

  it "clears temp files before preparing the database, so the seed's mail survives" do
    clone_with(nil)

    run_setup

    expect(logged.index("rails log:clear tmp:clear")).to be < logged.index("rails db:prepare")
  end

  # assets:clobber also deletes the Tailwind build, and --skip-server never reaches bin/dev to rebuild it.
  it "rebuilds the stylesheet after clearing precompiled assets, so system specs render styled" do
    clone_with(nil)

    run_setup

    expect(logged.index("rails tailwindcss:build")).to be > logged.index("rails assets:clobber")
  end

  it "does no fork setup in the template's own clone" do
    clone_with(nil)

    run_setup

    expect(app.join(".env")).not_to exist
    expect(git_value("config", "merge.ours.driver")).to be_empty
  end
end
