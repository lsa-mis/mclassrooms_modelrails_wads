# frozen_string_literal: true

require "rails_helper"

# Every vendored UI::* component's class-level comment is the three-line pointer
# to docs/components/<name>.md in the modelrails_ui gem; the prose lives there
# (modelrails_ui 0.16.0). The detector is inlined because the gem is
# development-only and is not loaded in the test group.
RSpec.describe "Component headers are pointers" do
  # A `let`, not a bare constant — a describe-level constant lands on Object
  # and can collide across parallel workers (#607); `header_block`/`pointer?`
  # are helper defs, so `let` is the sanctioned form.
  let(:doc_parent) do
    { "accordion_item" => "accordion", "list_group_item" => "list_group",
      "menubar_menu" => "menubar", "tabs_item" => "tabs",
      "card_content" => "card", "card_description" => "card", "card_footer" => "card",
      "card_header" => "card", "card_title" => "card" }.freeze
  end

  # Shared with the heading sweep below and its positive control, so both
  # judge the same pattern.
  let(:heading_regex) { /\A\s*# ##?\s+\S/ }

  # Contiguous `#` runs within lines[from...to], as Ranges.
  def comment_blocks(lines, from, to)
    ranges = []
    start = nil
    (from...to).each do |idx|
      if lines[idx].match?(/\A\s*#/)
        start ||= idx
      elsif start
        ranges << (start...idx)
        start = nil
      end
    end
    ranges << (start...to) if start
    ranges
  end

  def header_block(lines)
    i = lines.index { |l| l.match?(/\A\s*class\s+\S/) } or return []

    # A header can be severed from the class line by constants or a blank line
    # in between (e.g. card_title's header, then LEVELS/DEFAULT_LEVEL, then the
    # class), and an in-class doc comment right below `class` (e.g. range's
    # constant rationale) can otherwise out-length the real header above. An
    # already-migrated pointer block anywhere in the module-to-class region
    # wins outright, mirroring the gem's `locate` — but only when it is the
    # region's sole comment block; a leftover prose block sharing the region
    # with a pointer means the header hasn't fully migrated, so the full span
    # from the first block through the last is returned instead (its size
    # then fails `pointer?`). Below-`class` comments are judged only as the
    # fallback header when nothing above qualifies (e.g. audio/picture's
    # pointer, which sits below `class`); prose below `class` next to a
    # pointer above it is not this guard's case — a re-pasted heading there
    # is caught by the heading sweep below, a misindented block by
    # Layout/CommentIndentation.
    mod_idx = lines[0...i].rindex { |l| l.match?(/\A\s*module\s+\S/) }
    region_start = mod_idx ? mod_idx + 1 : 0
    blocks = comment_blocks(lines, region_start, i)
    marked = blocks.find { |r| lines[r].any? { |l| l.include?("docs/components/") } }
    if marked
      return lines[marked] if blocks.one?

      return lines[blocks.first.begin...blocks.last.end]
    end

    up_start = i
    up_start -= 1 while up_start.positive? && lines[up_start - 1].match?(/\A\s*#/)
    up = lines[up_start...i]
    up = [] if up.any? { |l| l.include?("frozen_string_literal") }
    down_end = i + 1
    down_end += 1 while down_end < lines.size && lines[down_end].match?(/\A\s*#/)
    down = lines[(i + 1)...down_end]
    up.size >= down.size ? up : down
  end

  def pointer?(name, lines)
    block = header_block(lines)
    block.size == 3 && block.any? { |l| l.include?("docs/components/#{doc_parent.fetch(name, name)}.md") }
  end

  it "keeps every vendored UI component's class comment to the three-line doc pointer" do
    offenders = Dir.glob(Rails.root.join("app/components/ui/*_component.rb")).reject do |file|
      pointer?(File.basename(file, "_component.rb"), File.readlines(file))
    end

    expect(offenders.map { |f| f.delete_prefix("#{Rails.root}/") }).to be_empty,
      "Grew back into prose — the reference lives in the gem's docs/components/<name>.md:\n  #{offenders.join("\n  ")}"
  end

  it "fails on a header that is prose (positive control)" do
    prose = [ "module UI\n", "  # # Kbd\n", "  #\n", "  # Long paragraph.\n", "  # ## Use when\n", "  # - always\n", "  class KbdComponent\n", "  end\n", "end\n" ]
    expect(pointer?("kbd", prose)).to be(false)
    pointer = [ "module UI\n", "  # Renders a key.\n", "  # See docs/components/kbd.md in the modelrails_ui gem.\n", "  # Live examples in Lookbook.\n", "  class KbdComponent\n", "  end\n", "end\n" ]
    expect(pointer?("kbd", pointer)).to be(true)

    # A pointer block that still shares the module-to-class region with a
    # leftover prose block above it (separated by a blank line) has not
    # fully migrated — the region holds more than one comment block, so the
    # fix in header_block returns the full span, which fails the size check.
    prose_above_pointer = [
      "module UI\n",
      "  # Some old paragraph.\n",
      "  # More of the old paragraph.\n",
      "\n",
      "  # Renders a key.\n",
      "  # See docs/components/kbd.md in the modelrails_ui gem.\n",
      "  # Live examples in Lookbook.\n",
      "  class KbdComponent\n",
      "  end\n",
      "end\n"
    ]
    expect(pointer?("kbd", prose_above_pointer)).to be(false)
  end

  it "keeps no markdown-heading comment in any vendored component" do
    # A nested `#` inside a commented code sample is not a heading — every real
    # header title/section line has exactly one space after the comment marker
    # (`# # Title`, `# ## Use when`), so the space is literal here.
    offenders = Dir.glob(Rails.root.join("app/components/ui/*_component.rb")).select do |file|
      File.readlines(file).any? { |l| l.match?(heading_regex) }
    end

    expect(offenders.map { |f| f.delete_prefix("#{Rails.root}/") }).to be_empty,
      "A markdown heading comment survived migration — the prose lives in the gem's docs/components/<name>.md:\n  #{offenders.join("\n  ")}"

    # Positive control. Without it, a typo in the regex could make the sweep
    # above pass vacuously by matching nothing at all.
    expect("  # # Kbd\n").to match(heading_regex)
    expect("  # ## Use when\n").to match(heading_regex)
    expect("  #   # nested sample\n").not_to match(heading_regex)
    expect("# frozen_string_literal: true\n").not_to match(heading_regex)
  end
end
