require "rails_helper"

# Type that is read or acted on stays readable: no 12px copy, unitless leading only, never justified,
# and a real ellipsis in copy (playbook standards/frontend/css.md and components.md).
RSpec.describe "Code smell: reading type" do
  def relative(path) = Pathname(path).relative_path_from(Rails.root).to_s

  def view_and_component_sources
    Dir[Rails.root.join("app/{views,components}/**/*.{erb,rb}")]
  end

  def small_copy(source)
    erb_tags = source.scan(/<(?:p|label|button)\b(?:[^>"]|"[^"]*")*>/).select { _1.match?(/\btext-xs\b/) }
    ruby_tags = source.scan(/content_tag\(?\s*:(?:p|label|button)\b[^\n]*/).select { _1.match?(/\btext-xs\b/) }
    erb_tags + ruby_tags
  end

  def fixed_leading_or_justify(source)
    source.scan(/\bleading-(?:\[[^\]]*\]|\d+(?:\.\d+)?)|\btext-justify\b|text-align:\s*justify/)
  end

  it "sets no reading or actionable copy in text-xs" do
    offenders = view_and_component_sources.flat_map { |path| small_copy(File.read(path)).map { "#{relative(path)}: #{_1.squish}" } }

    expect(offenders).to be_empty, "Use text-sm or larger:\n  #{offenders.join("\n  ")}"
  end

  it "uses only unitless named leading and never justifies text" do
    sources = view_and_component_sources + Dir[Rails.root.join("app/assets/tailwind/**/*.css")]
    offenders = sources.flat_map { |path| fixed_leading_or_justify(File.read(path)).map { "#{relative(path)}: #{_1}" } }

    expect(offenders).to be_empty, "Use leading-snug/normal/relaxed; align start:\n  #{offenders.join("\n  ")}"
  end

  it "writes a real ellipsis in English copy, never three dots" do
    offenders = Dir[Rails.root.join("config/locales/en/**/*.yml")].flat_map do |path|
      File.readlines(path).each_with_index.filter_map { |line, i| "#{relative(path)}:#{i + 1}" if line.match?(/:\s.*\.\.\./) }
    end

    expect(offenders).to be_empty, "Write … (U+2026) as a literal character:\n  #{offenders.join("\n  ")}"
  end

  it "catches each shape and lets the sanctioned ones through (positive control)" do
    expect(small_copy('<p class="text-xs text-text-muted">')).not_to be_empty
    expect(small_copy('<button data-action="a->b#c" class="btn text-xs">')).not_to be_empty
    expect(small_copy("content_tag(:p, hint, class: \"text-xs\")")).not_to be_empty
    expect(small_copy('<span class="text-xs">')).to be_empty
    expect(fixed_leading_or_justify("leading-6 leading-[18px] text-justify")).to eq(%w[leading-6 leading-[18px] text-justify])
    expect(fixed_leading_or_justify("leading-relaxed leading-snug")).to be_empty
  end
end
