require "rails_helper"
require "tmpdir"

# A throwaway repository: the subject is the script's git plumbing, which the
# unit spec for CommentBlockCheck cannot reach.
RSpec.describe "bin/comment-block-check --range" do
  let(:repo) { Pathname.new(Dir.mktmpdir) }
  let(:env) do
    CleanGitEnv::HASH.merge(
      "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s,
      "GIT_AUTHOR_NAME" => "spec", "GIT_AUTHOR_EMAIL" => "spec@example.com",
      "GIT_COMMITTER_NAME" => "spec", "GIT_COMMITTER_EMAIL" => "spec@example.com"
    )
  end

  after { FileUtils.rm_rf(repo) }

  def git(*args)
    system(env, "git", *args, chdir: repo.to_s, out: File::NULL, err: File::NULL) ||
      raise("git #{args.first} failed")
  end

  def commit(path, content, message)
    repo.join(path).dirname.mkpath
    repo.join(path).write(content)
    git("add", path)
    git("commit", "-q", "-m", message)
  end

  def check(range)
    output = IO.popen(env, [ Rails.root.join("bin/comment-block-check").to_s, "--range", range ],
                      chdir: repo.to_s, err: [ :child, :out ], &:read)
    [ $?.exitstatus, output ]
  end

  before do
    git("init", "-q", "-b", "main")
    commit("lib/thing.rb", "class Thing\nend\n", "base")
    git("branch", "base")
  end

  it "refuses a comment block over two lines added between base and head" do
    commit("lib/thing.rb", "# one\n# two\n# three\nclass Thing\nend\n", "head")

    status, output = check("base...HEAD")

    expect(status).to eq(1)
    expect(output).to include("lib/thing.rb:1-3 (3 lines)").and include("this pull request")
  end

  it "accepts a gist and a pointer" do
    commit("lib/thing.rb", "# gist\n# pointer\nclass Thing\nend\n", "head")

    expect(check("base...HEAD")).to eq([ 0, "" ])
  end

  it "leaves a long block alone when the range did not touch it" do
    commit("lib/other.rb", "# one\n# two\n# three\nclass Other\nend\n", "already on base")
    git("branch", "-f", "base")
    commit("lib/thing.rb", "class Thing\n  def call = true\nend\n", "head")

    expect(check("base...HEAD").first).to eq(0)
  end
end
