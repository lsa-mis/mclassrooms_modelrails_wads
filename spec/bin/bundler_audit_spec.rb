require "rails_helper"
require "open3"
require "tmpdir"

RSpec.describe "bin/bundler-audit" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = Pathname.new(dir)
      example.run
    end
  end

  def git(*args, chdir:) = system(CleanGitEnv::HASH, "git", *args.map(&:to_s), chdir: chdir.to_s, exception: true, out: File::NULL, err: File::NULL)
  def head(path) = IO.popen(CleanGitEnv::HASH, [ "git", "-C", path.to_s, "rev-parse", "HEAD" ], &:read).strip

  it "updates its advisory database from a linked worktree's pre-push hook, where git sets GIT_DIR" do
    upstream = @dir.join("advisory-upstream")
    database = @dir.join("advisory-db")
    hook_repo = @dir.join("hook-repo")
    git("init", "-q", "-b", "master", upstream, chdir: @dir)
    git("-c", "user.email=a@b.test", "-c", "user.name=A", "commit", "-q", "--allow-empty", "-m", "first", chdir: upstream)
    git("clone", "-q", upstream, database, chdir: @dir)
    git("-c", "user.email=a@b.test", "-c", "user.name=A", "commit", "-q", "--allow-empty", "-m", "advisory", chdir: upstream)
    git("init", "-q", hook_repo, chdir: @dir)

    env = { "BUNDLER_AUDIT_DB" => database.to_s, "GIT_DIR" => hook_repo.join(".git").to_s }
    output, status = Open3.capture2e(env, RbConfig.ruby, Rails.root.join("bin/bundler-audit").to_s, "update", chdir: Rails.root.to_s)

    expect(status).to be_success, output
    expect(head(database)).to eq(head(upstream))
  end
end
