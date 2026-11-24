require "rails_helper"
require "open3"
require "tmpdir"

RSpec.describe "bin/yaml-check" do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  let(:script) { Rails.root.join("bin/yaml-check").to_s }

  after { FileUtils.rm_rf(dir) }

  def check(*paths, chdir: dir.to_s)
    Open3.capture2e(script, *paths, chdir:)
  end

  def write(name, body)
    dir.join(name).write(body).then { name }
  end

  it "passes a file with aliases, symbols and dates" do
    file = write("good.yml", "base: &base\n  kind: :admin\n  on: 2026-11-13\ncopy:\n  <<: *base\n")

    _out, status = check(file)

    expect(status.exitstatus).to eq(0)
  end

  it "fails a malformed file and names it with its line" do
    file = write("bad.yml", "a: 1\n  b: [unclosed\n")

    out, status = check(file)

    expect(status.exitstatus).to eq(1)
    expect(out).to include("bad.yml:2")
  end

  it "skips an ERB-templated file it cannot parse raw" do
    file = write("templated.yml", "a: <%= ENV['X'] %>\n<% if true %>\nb: 1\n<% end %>\n")

    _out, status = check(file)

    expect(status.exitstatus).to eq(0)
  end

  it "passes every tracked YAML file in this repository" do
    tracked = IO.popen(CleanGitEnv::HASH, [ "git", "ls-files", "*.yml", "*.yaml" ], chdir: Rails.root.to_s, &:read)
                .lines(chomp: true)

    out, status = check(*tracked, chdir: Rails.root.to_s)

    expect(status.exitstatus).to eq(0), out
  end
end
