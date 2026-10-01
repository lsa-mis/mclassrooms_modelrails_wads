require "rails_helper"

# README's project tree is a newcomer's first map of the repo; an entry that
# no longer exists sends them looking for a file that was renamed or removed.
RSpec.describe "README project structure" do
  let(:tree_paths) do
    block = Rails.root.join("README.md").read[/^### Project structure\n+```\n(.*?)^```/m, 1].to_s
    parents = []
    block.lines.filter_map do |line|
      entry = line.sub(/#.*/, "").rstrip
      next if entry.strip.empty?

      depth = entry[/\A */].size / 2
      parents = parents.first(depth) << entry.strip
      parents.join("/").squeeze("/").delete_suffix("/")
    end
  end

  it "reads the tree it guards (floor and positive control)" do
    expect(tree_paths.size).to be >= 15
    expect(tree_paths).to include("app/controllers/concerns/authenticatable.rb", "app/mailers/magic_link_mailer.rb")
  end

  it "lists only paths that exist" do
    missing = tree_paths.reject { |path| Rails.root.join(path).exist? }

    expect(missing).to be_empty, "README's project tree lists paths that no longer exist: #{missing.join(', ')}"
  end
end
