# frozen_string_literal: true

require "rails_helper"
require "markdowndocs_local_categories"

RSpec.describe MarkdowndocsLocalCategories do
  let(:template) { { "Guides" => %w[extending], "Features" => %w[accounts] } }

  def with_local_file(content)
    Tempfile.create([ "categories", ".yml" ]) do |f|
      f.write(content)
      f.flush
      yield Pathname.new(f.path)
    end
  end

  # Fork-proofed: the original example asserted the REAL seam path
  # (config/markdowndocs_categories.local.yml) doesn't exist — which can
  # never hold in a fork that uses the documented seam. Test the same
  # missing-file behavior against a path that is absent by construction.
  # (Worth upstreaming to the template.)
  it "returns the template map untouched when no local file exists" do
    missing = Rails.root.join("config/definitely_absent_categories.local.yml")
    expect(File.exist?(missing)).to be(false)
    expect(described_class.merge(template, missing)).to eq(template)
  end

  it "adds new fork categories alongside template ones" do
    with_local_file("My Product:\n  - my-feature\n") do |path|
      result = described_class.merge(template, path)
      expect(result["My Product"]).to eq(%w[my-feature])
      expect(result["Guides"]).to eq(%w[extending])
    end
  end

  it "appends fork slugs when the fork extends an existing template category" do
    with_local_file("Guides:\n  - my-guide\n") do |path|
      expect(described_class.merge(template, path)["Guides"]).to eq(%w[extending my-guide])
    end
  end

  it "treats an empty local file as no categories" do
    with_local_file("") do |path|
      expect(described_class.merge(template, path)).to eq(template)
    end
  end
end
