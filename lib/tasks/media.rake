module Media
  module AltCoverage
    module_function

    # One row per model+slot: attached count + needs_review count.
    def report
      Rails.application.eager_load!
      Describable.registry.values.uniq.flat_map do |model|
        model.describable_slots.keys.map do |slot|
          attached_ids = ActiveStorage::Attachment
            .where(record_type: model.name, name: slot).pluck(:record_id)
          scope = model.where(id: attached_ids)
          needs = scope.count { |rec| rec.needs_alt_review?(slot) }
          { model: model.name, slot: slot, attached: attached_ids.size, needs_review: needs }
        end
      end
    end
  end
end

namespace :media do
  desc "Report which images still need authored alt text (informational; never fails)"
  task alt_coverage: :environment do
    rows = Media::AltCoverage.report
    total = rows.sum { |r| r[:needs_review] }
    puts format("%-20s %-16s %8s %14s", "MODEL", "SLOT", "ATTACHED", "NEEDS_REVIEW")
    rows.each do |r|
      puts format("%-20s %-16s %8d %14d", r[:model], r[:slot], r[:attached], r[:needs_review])
    end
    puts "-" * 62
    puts "#{total} image(s) still need authored alt text (on the derived backstop)."
  end

  desc "Process every declared variant for every media asset (WORKSPACE=slug)"
  task warm_variants: :environment do
    slug = ENV.fetch("WORKSPACE") { abort "WORKSPACE=<slug> is required" }
    workspace = Workspace.kept.find_by(slug: slug)
    abort "No kept workspace found for WORKSPACE=#{slug.inspect}" if workspace.nil?

    scope = MediaAsset.where(workspace: workspace)
    total = scope.count
    scope.find_each.with_index(1) do |asset, i|
      WarmMediaVariantsJob.perform_now(asset)
      puts "warmed #{i}/#{total}" if (i % 50).zero?
    end
    puts "done: #{total} assets"
  end
end
