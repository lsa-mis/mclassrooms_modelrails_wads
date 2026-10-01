require "rails_helper"

# A doc's `code:` front matter maps each feature it explains to the paths behind it
# (developer/conventions.md §Docs index their code); a path that moves fails here.
RSpec.describe "Documentation code index" do
  let(:front_matter) do
    Dir[Rails.root.join("app/docs/**/*.md")].sort.to_h do |file|
      text = File.read(file)
      meta = text.start_with?("---") ? YAML.safe_load(text.split(/^---\s*$/, 3)[1]) : {}
      [ Pathname(file).relative_path_from(Rails.root).to_s, meta || {} ]
    end
  end

  let(:indexes) { front_matter.select { |_, meta| meta.key?("code") }.transform_values { |meta| meta["code"] } }

  it "reads the front matter of every doc (floor)" do
    expect(front_matter.size).to be >= 41
  end

  it "finds the sign-up index it was written against (positive control)" do
    expect(indexes.dig("app/docs/developer/application-flows.md", "signup"))
      .to include("app/lib/oauth_link.rb", "app/controllers/magic_link_callbacks_controller.rb")
  end

  it "maps each feature to a list of paths" do
    malformed = indexes.reject do |_, features|
      features.is_a?(Hash) && features.values.all? { |paths| paths.is_a?(Array) && paths.any? && paths.all?(String) }
    end

    expect(malformed.keys).to be_empty,
      "code: must map feature names to non-empty lists of paths in: #{malformed.keys.join(', ')}"
  end

  it "indexes only paths that are in the repo" do
    missing = indexes.flat_map do |doc, features|
      Hash(features).flat_map do |feature, paths|
        Array(paths).reject { |path| tracked_path?(path) }.map { |path| "#{doc} (#{feature}) lists #{path}, which is not in the repo" }
      end
    end

    expect(missing).to be_empty, missing.join("\n")
  end

  it "leaves markdowndocs reading each indexed doc's front matter" do
    unread = indexes.keys.reject do |doc|
      Markdowndocs::Documentation.new(Rails.root.join(doc)).keywords == Array(front_matter[doc]["keywords"])
    end

    expect(unread).to be_empty, "markdowndocs no longer parses the front matter of: #{unread.join(', ')}"
  end
end
