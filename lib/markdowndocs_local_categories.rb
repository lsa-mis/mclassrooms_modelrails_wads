# frozen_string_literal: true

require "yaml"

# Fork seam: merges the optional fork-owned categories file
# (config/markdowndocs_categories.local.yml — absent upstream) into the
# template's /docs category map, so a downstream fork registers its own docs
# pages without editing template-owned files. Same-named categories append.
# Required explicitly by config/initializers/markdowndocs.rb (initializers
# cannot reference autoloaded constants under Zeitwerk). See /docs/forking.
module MarkdowndocsLocalCategories
  def self.merge(template_categories, local_path)
    return template_categories unless File.exist?(local_path)

    local_categories = YAML.load_file(local_path) || {}
    template_categories.merge(local_categories) do |_category, template_slugs, fork_slugs|
      template_slugs + fork_slugs
    end
  end
end
