require "rails_helper"

# scope: nil does not unscope a model-backed form_with: Rails falls back to the model's param key,
# so a controller reading params[:field] gets nothing. Unscoped params take scope: "" (#1369).
RSpec.describe "Code smell: a model-backed form_with never passes scope: nil" do
  def offending?(call)
    call.match?(/\bmodel:/) && call.match?(/\bscope:\s*nil\b/)
  end

  def form_with_calls(source)
    source.scan(/form_with\b.*?\bdo\b/m)
  end

  it "finds none in the views or components" do
    offenders = Dir[Rails.root.join("app/{views,components}/**/*.erb")].flat_map do |path|
      form_with_calls(File.read(path)).select { offending?(_1) }
        .map { "#{Pathname(path).relative_path_from(Rails.root)}: #{_1.squish}" }
    end

    expect(offenders).to be_empty,
      "Use scope: \"\" where the params must arrive unscoped:\n  #{offenders.join("\n  ")}"
  end

  it "catches the shape on one line or across several, and lets scope: \"\" through (positive control)" do
    one_line = '<%= form_with model: @lookup, url: lookup_path, scope: nil do |form| %>'
    split = "<%= form_with model: @lookup,\n      url: lookup_path,\n      scope: nil do |form| %>"
    fixed = '<%= form_with model: @lookup, url: lookup_path, scope: "" do |form| %>'

    expect(form_with_calls(one_line).count { offending?(_1) }).to eq(1)
    expect(form_with_calls(split).count { offending?(_1) }).to eq(1)
    expect(form_with_calls(fixed).count { offending?(_1) }).to eq(0)
  end
end
