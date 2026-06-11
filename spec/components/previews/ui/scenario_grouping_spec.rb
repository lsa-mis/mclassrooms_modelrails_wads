# frozen_string_literal: true

require "rails_helper"

# Mirror of the gem guard: every app preview with meta scenarios (showcase/playground/dont_*)
# must group into Overview/Examples/Reference in canonical order; canonical-only stay flat.
RSpec.describe "Lookbook scenario grouping" do
  preview_root = Rails.root.join("spec/components/previews/ui")
  rank = { overview: 0, examples: 1, reference_pg: 2, reference_dont: 3 }

  classify = lambda do |name|
    next :overview if name == "showcase"
    next :reference_pg if name == "playground"
    next :reference_dont if name.start_with?("dont_")
    :examples
  end

  Dir.glob(preview_root.join("*_component_preview.rb")).sort.each do |path|
    component = File.basename(path, "_component_preview.rb")
    src = File.read(path)
    methods = src.scan(/^\s+def ([a-z_][a-z0-9_]*)/).flatten - %w[input_attrs]
    labels = src.scan(/^\s*#\s*@!group\s+(\w+)/).flatten
    has_meta = methods.any? { |m| m == "showcase" || m == "playground" || m.start_with?("dont_") }

    if has_meta
      it "#{component} groups scenarios in canonical order" do
        ranks = methods.map { |m| rank.fetch(classify.call(m)) }
        expect(ranks).to eq(ranks.sort), "out of order: #{methods.inspect}"
        expected = []
        expected << "Overview" if methods.include?("showcase")
        expected << "Examples"
        expected << "Reference"
        expect(labels).to eq(expected)
      end
    else
      it "#{component} (canonical-only) stays flat" do
        expect(labels).to be_empty
      end
    end
  end
end
