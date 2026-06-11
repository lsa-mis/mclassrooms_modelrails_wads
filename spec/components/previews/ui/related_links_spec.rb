# frozen_string_literal: true

require "rails_helper"

# `## Related` doc-comment sections encode the sibling-relationship graph. Every
# backticked name inside one must be a real component preview — typo/drift protection,
# same static-analysis idiom as logical_path_coverage_spec.rb.
RSpec.describe "Lookbook Related cross-links" do
  preview_root = Rails.root.join("spec/components/previews/ui")
  names = Dir.glob(preview_root.join("*_component_preview.rb"))
    .map { |p| File.basename(p, "_component_preview.rb") }

  related_files = Dir.glob(preview_root.join("*_component_preview.rb")).sort.filter_map do |path|
    lines = File.read(path).lines
    idx = lines.index { |l| l.match?(/^\s*#\s*## Related\s*$/) }
    next unless idx

    block = lines[(idx + 1)..].take_while { |l| l.match?(/^\s*#/) && !l.match?(/^\s*#\s*(##|@)/) }.join
    [ File.basename(path, "_component_preview.rb"), block ]
  end

  it "encodes the relationship graph (at least one Related section exists)" do
    expect(related_files).not_to be_empty
  end

  related_files.each do |component, block|
    it "#{component}: every Related target is a real component" do
      targets = block.scan(/`([a-z_]+)`/).flatten.uniq
      expect(targets).not_to be_empty, "#{component}: empty ## Related section"
      missing = targets - names
      expect(missing).to be_empty, "#{component}: Related references unknown component(s): #{missing.join(", ")}"
    end
  end
end
