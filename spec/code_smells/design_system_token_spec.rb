require "rails_helper"

# Design-system component utilities live in application.css's @layer
# components block. A class declared in @layer utilities instead wins
# Tailwind v4 cascade ties over components it shouldn't — a real correctness
# issue, not just a doc nit (caught during the 2026-07-02 header-spacing
# design-panel review: Adam Wathan, Chris Oliver).
RSpec.describe "Design-system CSS layer discipline" do
  let(:application_css) { File.read(Rails.root.join("app/assets/tailwind/application.css")) }

  # A crude but sufficient block extractor: find `@layer <name> {`, then walk
  # forward counting braces until the matching close.
  def layer_block(css, layer_name)
    start = css.index("@layer #{layer_name} {")
    return nil unless start

    depth = 0
    i = css.index("{", start)
    block_start = i
    loop do
      case css[i]
      when "{" then depth += 1
      when "}" then depth -= 1
      end
      break if depth.zero?
      i += 1
    end
    css[block_start..i]
  end

  it ".page-container is declared in @layer components" do
    components_block = layer_block(application_css, "components")
    utilities_block = layer_block(application_css, "utilities")

    expect(components_block).to include(".page-container"),
      "expected .page-container inside @layer components, with the rest of the " \
      "design-system component utilities"
    expect(utilities_block.to_s).not_to include(".page-container"),
      ".page-container is still declared in @layer utilities — utilities-layer rules win " \
      "cascade ties over components-layer rules of equal specificity in Tailwind v4, so this " \
      "isn't cosmetic. Move the declaration into the @layer components block."
  end

  it "--space-section-gap has at least one consumer (no phantom tokens)" do
    spacing_tokens = File.read(Rails.root.join("app/assets/tailwind/tokens/_spacing.css"))
    next unless spacing_tokens.include?("--space-section-gap")

    consumers = application_css.scan(/var\(--space-section-gap\)/)
    expect(consumers).not_to be_empty,
      "--space-section-gap is defined in _spacing.css but has zero consumers in " \
      "application.css. A token nobody reaches for is worse than no token — it makes the " \
      "design system look more governed than it is. Wire it into a @layer components rule " \
      "or delete it."
  end

  # The sibling failure, and a shipped one rather than a hypothetical:
  # min-h-input was registered with a "prefer it" comment and 81 legacy spellings
  # accreted anyway, because nothing failed. Documenting a preference did not work,
  # so this asserts it (#1105).
  #
  # Not cosmetic. --form-input-height is the documented retune knob, so a fork that
  # sets it to 48px moves every min-h-input and leaves every min-h-11 at 44 — the
  # page silently splits into two heights.
  #
  # app/components/ui/** used to be excluded: those files are vendored from
  # modelrails_ui, and this scan was to widen "once the gem-side sweep lands".
  # It landed in v0.23.0 (gem #252, 32 sites across 26 files), so the exclusion
  # is gone and the vendored copies are held to the same rule as the app's own.
  #
  # ONE exemption, and it is not an input. mega_menu's ITEM_CLS is a navigation
  # LINK at the 2.5.5 target floor; --form-input-height is the form-control
  # knob, so a fork retuning it should move every input and leave a nav link
  # where it is. A path, not a file:line — a line number goes stale the moment
  # anything is inserted above it.
  # `let`, not a bare constant: a SCREAMING_CASE constant in a describe block
  # lands on Object and collides across parallel workers (#607).
  let(:nav_target_floor) { "app/components/ui/mega_menu_component.rb" }

  it "spells the input-height floor as min-h-input, not as a raw value" do
    legacy = /\bmin-h-11\b|min-h-\[var\(--form-input-height\)\]/
    roots = Dir[Rails.root.join("app/views/**/*.erb")] +
            Dir[Rails.root.join("app/components/**/*.{rb,erb}")] +
            Dir[Rails.root.join("app/form_builders/**/*.rb")]

    offenders = roots.select { |path| File.read(path).match?(legacy) }
                     .map { |path| Pathname.new(path).relative_path_from(Rails.root).to_s }
                     .reject { |path| path == nav_target_floor }

    expect(offenders).to be_empty,
      "these spell the 44px input floor as a raw value instead of min-h-input, so a fork " \
      "that retunes --form-input-height leaves them behind:\n  #{offenders.join("\n  ")}"
  end

  # The exemption has to keep naming something, or it silently becomes a
  # no-op entry nobody removes.
  it "keeps the one nav-target-floor exemption pointing at a real use" do
    path = Rails.root.join(nav_target_floor)

    expect(path).to exist, "#{nav_target_floor} is gone — drop the exemption"
    expect(File.read(path)).to match(/\bmin-h-11\b/),
      "#{nav_target_floor} no longer spells a raw 44px floor, so the exemption is dead — drop it"
  end
end
