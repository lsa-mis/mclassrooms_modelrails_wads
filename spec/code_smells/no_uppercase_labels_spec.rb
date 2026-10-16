require "rails_helper"

# There is no uppercase label style: a group label is text-sm font-medium in sentence case
# (playbook standards/frontend/components.md). Uppercase stays legal only beside font-mono, for codes.
RSpec.describe "Code smell: no uppercase label style" do
  def offending_strings(source)
    source.scan(/"[^"\n]*"|'[^'\n]*'/).select do |literal|
      literal.match?(/(?<![\w-])uppercase(?![\w-])/) && !literal.match?(/\bfont-mono\b/)
    end
  end

  it "finds no uppercase class outside a font-mono string in views, components or helpers" do
    offenders = Dir[Rails.root.join("app/{views,components,helpers}/**/*.{erb,rb}")].flat_map do |path|
      offending_strings(File.read(path)).map { "#{Pathname(path).relative_path_from(Rails.root)}: #{_1}" }
    end

    expect(offenders).to be_empty,
      "Write the label in sentence case as text-sm font-medium:\n  #{offenders.join("\n  ")}"
  end

  it "catches a bare or variant-prefixed uppercase class and lets font-mono codes through (positive control)" do
    expect(offending_strings('<h2 class="text-xs font-semibold uppercase tracking-wider">')).not_to be_empty
    expect(offending_strings("LABEL = 'md:uppercase text-xs'")).not_to be_empty
    expect(offending_strings('<code class="font-mono uppercase">')).to be_empty
    expect(offending_strings("# sorts uppercase before lowercase")).to be_empty
  end
end
