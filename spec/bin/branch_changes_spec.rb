require "rails_helper"
require "open3"
require "tmpdir"

RSpec.describe "bin/branch-changes" do
  let(:repo) { Pathname.new(Dir.mktmpdir) }
  let(:script) { Rails.root.join("bin/branch-changes").to_s }

  after { FileUtils.rm_rf(repo) }

  def commit_file(name)
    repo.join(name).write("x\n")
    scratch_git(repo, "add", name)
    scratch_git(repo, "commit", "-qm", name)
  end

  def changes
    out, status = Open3.capture2(CleanGitEnv::HASH, script, chdir: repo.to_s)
    raise "exit #{status.exitstatus}" unless status.success?

    out.lines(chomp: true)
  end

  before do
    scratch_git(repo, "init", "-q", "-b", "work")
    commit_file("old.txt")
  end

  it "compares with origin/main when it exists, as on a fork with both branches" do
    scratch_git(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
    scratch_git(repo, "update-ref", "refs/remotes/origin/next", "HEAD")
    commit_file("on_next.txt")
    scratch_git(repo, "update-ref", "refs/remotes/origin/next", "HEAD")
    commit_file("new.txt")

    expect(changes).to contain_exactly("on_next.txt", "new.txt")
  end

  it "compares with origin/next on a Fork-button fork, which has no main yet" do
    scratch_git(repo, "update-ref", "refs/remotes/origin/next", "HEAD")
    commit_file("new.txt")

    expect(changes).to eq([ "new.txt" ])
  end

  it "lists every tracked file on a first push to an empty repository" do
    commit_file("new.txt")

    expect(changes).to contain_exactly("old.txt", "new.txt")
  end
end
