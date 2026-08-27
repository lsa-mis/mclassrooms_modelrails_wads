require "rails_helper"

# An absence assertion proves nothing by itself: `have_no_css` is satisfied by
# a 500, a redirect, and a blank page alike. Two examples of exactly that shape
# were removed in #847 after passing with the element deleted, the controller
# deleted, and on a blank page; #853 found eight more live, one of them guarding
# whether destructive workspace controls are hidden — green on a 403 redirect.
#
# The rule: every Capybara negative matcher must share its page state with a
# positive anchor — an assertion or interaction that can only succeed once the
# page it means to interrogate has actually rendered. Anchors do NOT survive a
# navigation (`visit`/`page.refresh` land on a new document), so the anchor
# must come after the last navigation before the negation. Where an element
# exists but should be invisible, pair `have_css(..., visible: :hidden)` with
# `have_no_css(..., visible: true)` — the idiom in footer_cookies_spec.
#
# Scan bias, per the code-smells house rule: heuristics may only MISS a
# violation, never invent one. Block boundaries can only split a block;
# unrecognized anchors (a helper matched in a comment, say) can only anchor a
# segment that should have flagged. Interaction methods count as anchors
# because they raise when their target is missing; so does calling a helper
# whose own body anchors (found by scanning `def` blocks here and in
# spec/support — e.g. `sign_in_via_form`, the `open_modal` family).
RSpec.describe "Absence assertions are anchored" do
  def block_start_pattern = /^\s*(it|specify|scenario|before|after|def)\b/

  def navigation_pattern = /^\s*visit\b|page\.refresh/

  def negative_matcher_pattern = /\.to have_no_\w+|not_to have_\w+|to_not have_\w+/

  def anchor_pattern
    /\.to[ ]have_(?!no_)\w+|
     \b(find|find_button|find_link|find_field|click_button|click_link|click_on|
        fill_in|uncheck|check|choose|select|attach_file|within)[\s(]/x
  end

  def blocks_in(source)
    source.each_line.with_index(1).slice_before { |line, _| line.match?(block_start_pattern) }
  end

  # Names of methods whose body contains an anchor — calling one anchors the
  # caller's segment exactly as an inline find/expect would.
  def anchoring_helpers_in(paths)
    paths.flat_map { |path|
      blocks_in(File.read(path)).filter_map do |block|
        name = block.first.first[/^\s*def\s+(\w+)/, 1]
        name if name && block.any? { |line, _| line.match?(anchor_pattern) }
      end
    }.uniq
  end

  def support_anchoring_helpers
    @support_anchoring_helpers ||= anchoring_helpers_in(Dir[Rails.root.join("spec/support/**/*.rb")])
  end

  def anchored?(segment, helper_pattern)
    segment.any? { |line, _| line.match?(anchor_pattern) || line.match?(helper_pattern) }
  end

  def violations_in(path)
    helpers = support_anchoring_helpers + anchoring_helpers_in([ path ])
    helper_pattern = /\b(#{helpers.map { |name| Regexp.escape(name) }.join("|")})\b/

    blocks_in(File.read(path)).flat_map do |block|
      block.slice_before { |line, _| line.match?(navigation_pattern) }.filter_map do |segment|
        next unless segment.first.first.match?(navigation_pattern)

        negative = segment.find { |line, _| line.match?(negative_matcher_pattern) }
        next unless negative
        next if anchored?(segment, helper_pattern)

        "#{path.relative_path_from(Rails.root)}:#{negative.last}"
      end
    end
  end

  it "pairs every post-navigation negative matcher with a positive anchor" do
    offenders = Rails.root.glob("spec/system/**/*_spec.rb").sort.flat_map { |path| violations_in(path) }

    expect(offenders).to be_empty, <<~MSG
      These examples navigate and then assert only absence — they pass unchanged
      on a 500, a redirect, and a blank page, so they cannot fail on the
      regression they exist to catch:

      #{offenders.join("\n")}

      Before the negation (and after the LAST visit/refresh — anchors do not
      survive a navigation), assert something that can only hold once the page
      being interrogated has rendered: a heading, the row the element would sit
      in, the control that replaced it. For present-but-invisible elements, pair
      `have_css(..., visible: :hidden)` with `have_no_css(..., visible: true)`
      (see spec/system/footer_cookies_spec.rb).
    MSG
  end
end
