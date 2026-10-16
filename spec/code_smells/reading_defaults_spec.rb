require "rails_helper"

# The reading defaults live once, in CSS, so no view has to remember them
# (playbook standards/frontend/css.md, Reading type and layout defaults; accessibility.md 1.4.8).
RSpec.describe "Code smell: reading defaults" do
  def css(name) = Rails.root.join("app/assets/tailwind", name).read

  def base_layer_rules(source)
    source.scan(/@layer base\s*\{(.*?)\n\}/m).flatten.join("\n")
  end

  def viewport_height_units(source)
    source.scan(/\b\d*vh\b|\b(?:min-|max-)?h-screen\b/)
  end

  it "balances h1 to h3 and turns ligatures off for codes, once, in @layer base" do
    base = base_layer_rules(css("application.css"))

    expect(base).to match(/h1,\s*h2,\s*h3\s*\{[^}]*text-wrap:\s*balance/)
    expect(base).to match(/code,\s*kbd,\s*\.font-mono\s*\{[^}]*font-variant-ligatures:\s*none/)
  end

  it "holds .prose to a reading measure and paragraph spacing of 1.5 times the line height" do
    prose = css("_prose.css")

    expect(prose).to match(/\.prose\s*\{[^}]*max-w-prose/)
    expect(prose).to match(/\.prose p\s*\{[^}]*margin-block-end:\s*1\.5lh/)
  end

  it "sizes nothing by vh: 100vh counts the mobile browser bars, so views use dvh" do
    sources = Dir[Rails.root.join("app/{views,components}/**/*.{erb,rb}")] +
              Dir[Rails.root.join("app/assets/tailwind/**/*.css")]
    offenders = sources.flat_map do |path|
      viewport_height_units(File.read(path)).map { "#{Pathname(path).relative_path_from(Rails.root)}: #{_1}" }
    end

    expect(offenders).to be_empty, "Use dvh (min-h-dvh, 100dvh):\n  #{offenders.join("\n  ")}"
  end

  it "catches vh and h-screen but not dvh (positive control)" do
    expect(viewport_height_units('class="min-h-screen max-h-[calc(100vh-3rem)]"')).to eq(%w[min-h-screen 100vh])
    expect(viewport_height_units('class="min-h-dvh max-h-[calc(100dvh-3rem)]"')).to be_empty
  end
end
