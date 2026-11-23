require "rails_helper"
require "open3"
require "tmpdir"

RSpec.describe "bin/test-plan" do
  let(:repo) { Pathname.new(Dir.mktmpdir) }
  let(:script) { Rails.root.join("bin/test-plan").to_s }

  after { FileUtils.rm_rf(repo) }

  def commit_file(name, body = "x\n")
    repo.join(name).dirname.mkpath
    repo.join(name).write(body)
    scratch_git(repo, "add", name)
    scratch_git(repo, "commit", "-qm", name)
  end

  def test_plan(*args, env: {})
    Open3.capture2e(CleanGitEnv::HASH.merge(env), script, *args, chdir: repo.to_s)
  end

  before do
    scratch_git(repo, "init", "-q", "-b", "main")
    commit_file("spec/i18n_spec.rb")
    scratch_git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
    scratch_git(repo, "checkout", "-q", "-b", "next")
    commit_file("app/models/x.rb", "class X\nend\n")
    scratch_git(repo, "update-ref", "refs/remotes/origin/next", "HEAD")
    scratch_git(repo, "checkout", "-q", "-b", "work")
  end

  context "with a locale-only branch cut from next while next is ahead of main" do
    before { commit_file("config/locales/en.yml", "en:\n  hi: Hi\n") }

    it "classifies it as locale" do
      out, status = test_plan

      expect(status.exitstatus).to eq(0)
      expect(out.lines(chomp: true)).to eq([ "lanes: locale", "spec/i18n_spec.rb" ])
    end

    it "counts an uncommitted edit, since it runs before the commit" do
      repo.join("app/models/x.rb").write("class X\n  def y = 1\nend\n")

      out, _status = test_plan

      expect(out).to start_with("lanes: full\n")
    end

    it "counts an untracked file" do
      repo.join("app/models/y.rb").write("class Y\nend\n")

      out, _status = test_plan

      expect(out).to start_with("lanes: full\n")
    end

    it "honours --base" do
      out, _status = test_plan("--base", "origin/main")

      expect(out).to include("lanes: full")
    end

    it "writes full and specs to GITHUB_OUTPUT" do
      output = repo.join("github_output")

      _out, status = test_plan("--github-output", env: { "GITHUB_OUTPUT" => output.to_s })

      expect(status.exitstatus).to eq(0)
      expect(output.read.lines(chomp: true)).to eq([ "full=false", "specs=spec/i18n_spec.rb" ])
    end

    it "seeds before running specs, and runs them without coverage instrumentation" do
      out, status = test_plan("--run", "--dry-run")

      expect(status.exitstatus).to eq(0)
      expect(out.lines(chomp: true)).to eq([
        "lanes: locale",
        "RAILS_ENV=test bin/rails db:setup",
        "SKIP_COVERAGE=1 bundle exec rspec spec/i18n_spec.rb"
      ])
    end
  end

  it "is full when a code file is renamed into a docs-lane path" do
    scratch_git(repo, "mv", "app/models/x.rb", "README.md")
    scratch_git(repo, "commit", "-qm", "rename")

    out, _status = test_plan

    expect(out).to start_with("lanes: full\n")
  end

  it "never hands rspec an empty list, which would run the whole suite" do
    scratch_git(repo, "rm", "-q", "spec/i18n_spec.rb")
    scratch_git(repo, "commit", "-qm", "drop spec")
    scratch_git(repo, "update-ref", "refs/remotes/origin/next", "HEAD")
    commit_file("config/locales/en.yml", "en:\n  hi: Hi\n")

    out, status = test_plan("--run")

    expect(status.exitstatus).to eq(0)
    expect(out).to eq("lanes: locale\ntest-plan: no specs selected\n")
  end
end
