# frozen_string_literal: true

namespace :tailwind do
  desc "Create symlinks for gem view sources so Tailwind can scan them portably"
  task setup_gem_sources: :environment do
    vendor_dir = Rails.root.join("vendor")
    FileUtils.mkdir_p(vendor_dir)

    markdowndocs_path = Gem.loaded_specs["markdowndocs"]&.full_gem_path
    if markdowndocs_path
      target = vendor_dir.join("markdowndocs_views")
      source = File.join(markdowndocs_path, "app/views")
      # Remove an existing symlink BEFORE relinking: `ln_sf` dereferences a
      # symlink whose target is a directory and creates the new link INSIDE
      # it (polluting the old gem dir) instead of replacing the symlink — so
      # a gem-version bump would silently keep pointing at the old version.
      FileUtils.rm_f(target) if File.symlink?(target)
      FileUtils.ln_s(source, target)
      puts "Linked #{target} → #{source}"
    end
  end
end
