require "rails_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Generated production config outputs" do
  def regenerate_into(dir)
    FileUtils.mkdir_p(File.join(dir, "config"))
    %w[required_production_config.yml required_production_config.local.yml].each do |name|
      source = Rails.root.join("config", name)
      FileUtils.cp(source, File.join(dir, "config")) if source.exist?
    end
    RequiredProductionConfigCatalog::Generator.write(root: Pathname(dir))
  end

  it "keeps the committed docs page and example current" do
    Dir.mktmpdir do |dir|
      regenerate_into(dir)

      %w[app/docs/developer/required-production-config.md config/credentials/production.yml.example].each do |path|
        expect(Rails.root.join(path).read).to eq(File.read(File.join(dir, path))),
          "#{path} is stale; run bin/rails required_production_config:generate"
      end
    end
  end

  it "keeps a fork's local example current" do
    skip "no local catalog file upstream" unless Rails.root.join(RequiredProductionConfigCatalog::LOCAL_PATH).exist?

    Dir.mktmpdir do |dir|
      regenerate_into(dir)
      path = "config/credentials/production.local.yml.example"
      committed = Rails.root.join(path)
      written = File.join(dir, path)

      expect(committed.exist?).to eq(File.exist?(written))
      expect(committed.read).to eq(File.read(written)) if committed.exist?
    end
  end
end
