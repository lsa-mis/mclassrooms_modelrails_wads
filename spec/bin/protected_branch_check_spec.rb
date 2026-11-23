require "rails_helper"
require "open3"
require "tmpdir"

RSpec.describe "bin/protected-branch-check" do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  let(:remote) { dir.join("remote.git") }
  let(:repo) { dir.join("work") }
  let(:script) { Rails.root.join("bin/protected-branch-check").to_s }

  after { FileUtils.rm_rf(dir) }

  def commit(name)
    repo.join(name).write("#{name}\n")
    scratch_git(repo, "add", name)
    scratch_git(repo, "commit", "-qm", name)
  end

  def push(*args)
    Open3.capture2e(CleanGitEnv::HASH, "git", *args, chdir: repo.to_s)
  end

  def remote_has?(ref)
    system(CleanGitEnv::HASH, "git", "--git-dir", remote.to_s, "rev-parse", "--verify", "-q", ref, out: File::NULL)
  end

  before do
    scratch_git(dir, "init", "-q", "--bare", remote.to_s)
    scratch_git(dir, "init", "-q", "-b", "next", repo.to_s)
    scratch_git(repo, "remote", "add", "origin", remote.to_s)
    hook = repo.join(".git/hooks/pre-push")
    hook.write("#!/bin/sh\nexec #{script} \"$1\"\n")
    hook.chmod(0o755)
    commit("first")
  end

  # Lefthook shows a use_stdin command's stdout and drops its stderr.
  it "prints the refusal on stdout" do
    line = "refs/heads/next #{"b" * 40} refs/heads/next #{"a" * 40}\n"

    out, err, status = Open3.capture3(CleanGitEnv::HASH, script, "origin", stdin_data: line, chdir: repo.to_s)

    expect(status.exitstatus).to eq(1)
    expect(out).to include("gh pr create --base next")
    expect(err).to be_empty
  end

  it "lets bin/fork's first push create next on a brand-new repository" do
    _, status = push("push", "-u", "origin", "next")

    expect(status).to be_success
    expect(remote_has?("next")).to be(true)
  end

  context "when origin already has next" do
    before do
      push("push", "-q", "origin", "next")
      commit("second")
    end

    it "refuses a commit on next, with the way to a pull request" do
      out, status = push("push", "origin", "next")

      expect(status).not_to be_success
      expect(out).to include("origin's next only takes pull requests", "git branch -f next origin/next", "gh pr create --base next")
      expect(capture_remote_next).not_to eq(head)
    end

    it "lets bin/fork push a Fork-button fork's next before bin/branch-rules protects it" do
      _, status = push("-c", "branch-rules.off=next", "push", "-u", "origin", "next")

      expect(status).to be_success
      expect(capture_remote_next).to eq(head)
    end

    it "lets the emergency hotfix push main once its ruleset is switched off" do
      push("push", "-q", "origin", "next~1:refs/heads/main")
      scratch_git(repo, "switch", "-q", "-c", "hotfix/sign-in-loop")

      refused, = push("push", "origin", "hotfix/sign-in-loop:main")
      _, status = push("-c", "branch-rules.off=main", "push", "origin", "hotfix/sign-in-loop:main")

      expect(refused).to include("origin's main only takes pull requests", "git push -u origin hotfix/sign-in-loop")
      expect(status).to be_success
    end

    it "lets a feature branch through, as bin/release and bin/sync push theirs" do
      scratch_git(repo, "switch", "-q", "-c", "release/2026.11.14")

      _, status = push("push", "-u", "origin", "release/2026.11.14")

      expect(status).to be_success
    end

    it "lets a tag through" do
      scratch_git(repo, "tag", "v2026.11.14")

      _, status = push("push", "origin", "v2026.11.14")

      expect(status).to be_success
    end

    it "refuses deleting next" do
      out, status = push("push", "origin", "--delete", "next")

      expect(status).not_to be_success
      expect(out).to include("origin's next is protected")
      expect(remote_has?("next")).to be(true)
    end
  end

  def head = Open3.capture2(CleanGitEnv::HASH, "git", "rev-parse", "HEAD", chdir: repo.to_s).first.chomp

  def capture_remote_next
    Open3.capture2(CleanGitEnv::HASH, "git", "--git-dir", remote.to_s, "rev-parse", "next").first.chomp
  end
end
