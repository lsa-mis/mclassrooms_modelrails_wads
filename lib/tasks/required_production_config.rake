namespace :required_production_config do
  desc "Regenerate the production config docs page and credentials examples from the catalog"
  task generate: :environment do
    RequiredProductionConfigCatalog::Generator.write(root: Rails.root).each { |path| puts "wrote #{path}" }
  end
end
