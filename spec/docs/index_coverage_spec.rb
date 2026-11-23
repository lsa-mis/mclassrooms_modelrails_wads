require "rails_helper"

# Guards the docs *journey*, not just the docs. Every file in app/docs/ must be
# reachable from the /docs index — i.e. assigned to a category in
# config/initializers/markdowndocs.rb. An uncategorized doc still renders by
# direct URL but is invisible to a newcomer browsing the index, which is how
# the most important doc (presets) silently went missing. This guard fails CI
# the moment a new doc is added without a home.
RSpec.describe "Documentation index coverage" do
  let(:doc_slugs) do
    base = Rails.root.join("app/docs")
    Dir[base.join("**/*.md")].map { |f| Pathname(f).relative_path_from(base).to_s.delete_suffix(".md") }
  end
  let(:categorized) { Markdowndocs.configuration.categories.values.flatten }

  it "assigns every app/docs file to a category (no orphans hidden from the index)" do
    orphans = doc_slugs - categorized
    expect(orphans).to be_empty,
      "Uncategorized docs (add to config/initializers/markdowndocs.rb): #{orphans.sort.join(', ')}"
  end

  it "lists the Quickstart first among the developer pages under Getting Started" do
    developer_pages = Markdowndocs.configuration.categories.fetch("Getting Started").grep(%r{\Adeveloper/})

    expect(developer_pages.first).to eq("developer/quickstart")
    expect(Rails.root.join("app/docs/developer/quickstart.md").read).to start_with("---\ntitle: Quickstart\n")
  end

  %w[development production].zip(%w[developer user]).each do |environment, mode|
    it "opens the docs index on the #{mode} guide in #{environment}" do
      original = Markdowndocs.configuration.default_mode
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(environment))

      load Rails.root.join("config/initializers/markdowndocs.rb")

      expect(Markdowndocs.configuration.default_mode).to eq(mode)
    ensure
      Markdowndocs.configuration.default_mode = original
    end
  end

  it "references no category slug that lacks a backing file (catches renames/typos)" do
    stale = categorized - doc_slugs
    expect(stale).to be_empty,
      "Categorized slugs with no app/docs/*.md file: #{stale.sort.join(', ')}"
  end
end
