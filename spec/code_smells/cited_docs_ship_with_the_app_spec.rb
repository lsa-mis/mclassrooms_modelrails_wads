require "rails_helper"
require "open3"
require Rails.root.join("lib/clean_git_env").to_s

RSpec.describe "Docs cited from tracked files" do
  let(:citation) { %r{(?<![\w/.-])(docs/[\w./-]+\.md)} }
  let(:gem_docs_root) { Pathname(Gem.loaded_specs.fetch("modelrails_ui").full_gem_path) }

  let(:tracked) do
    listed, status = Open3.capture2(CleanGitEnv::HASH, "git", "ls-files", "-z", chdir: Rails.root.to_s)
    raise "git ls-files failed" unless status.success?

    listed.split("\0")
  end

  let(:citations) do
    tracked.grep(/\.(rb|erb|css|js|yml|md|rake)\z/).select { |path| Rails.root.join(path).file? }.flat_map do |path|
      lines = Rails.root.join(path).read.lines(chomp: true)
      lines.each_with_index.flat_map do |line, index|
        context = "#{line} #{lines[index + 1]}"
        line.scan(citation).map { |(cited)| { cited:, at: "#{path}:#{index + 1}", context: } }
      end
    end
  end

  def opens?(citation)
    return true if tracked.include?(citation[:cited])

    citation[:context].include?("modelrails_ui") && gem_docs_root.join(citation[:cited]).file?
  end

  context "with a tracked file deleted but not yet committed" do
    let(:tracked) { super() + [ "app/models/deleted_before_commit.rb" ] }

    it "scans what is on disk" do
      expect { citations }.not_to raise_error
    end
  end

  it "scans the component headers that cite modelrails_ui's docs (floor)" do
    expect(citations.count { |c| c[:cited].start_with?("docs/components/") }).to be > 50
  end

  it "cites only docs a fork can open: tracked here, or named as modelrails_ui's and present in the gem" do
    unopenable = citations.reject { |c| opens?(c) }

    expect(unopenable).to be_empty,
      "these cite a docs/ page a fork can't open (root docs/ isn't shipped):\n  " \
      "#{unopenable.map { |c| "#{c[:at]} #{c[:cited]}" }.join("\n  ")}\n" \
      "Point at the /docs page that tells the story, name modelrails_ui's page as the gem's, or drop the pointer."
  end
end
