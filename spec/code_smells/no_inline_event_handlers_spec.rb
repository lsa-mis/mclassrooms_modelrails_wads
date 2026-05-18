require "rails_helper"

# Inline event handlers like onchange="..." or onclick="..." are blocked by
# this project's strict CSP (script_src does not include unsafe_inline).
# The browser silently drops them, producing dead UI in dev/prod even though
# Capybara's :playwright driver dispatches events at the CDP level and so
# functional system specs can pass — see PR #119's discovery.
#
# This spec scans every committed .erb view for inline event handlers and
# fails the suite if any exist. The fix is always the same: use a Stimulus
# action (data: { action: "event->controller#method" }) instead.
RSpec.describe "ERB views have no inline event handlers" do
  # Standard DOM event attributes a browser would parse and execute as JS.
  # Listed explicitly (rather than a single broad on\w+ pattern) so the
  # failure message can suggest the specific Stimulus action equivalent
  # and so we don't accidentally trip on legitimate attributes named
  # something like data-only-once.
  FORBIDDEN_HANDLERS = %w[
    onclick onchange oninput onsubmit onload onunload
    onblur onfocus onkeyup onkeydown onkeypress
    onmouseover onmouseout onmousedown onmouseup onmousemove
    onsearch onreset onselect onscroll onwheel
    ondragstart ondragend ondragover ondragenter ondragleave ondrop
    ontoggle oncontextmenu ondblclick
  ].freeze

  it "uses Stimulus actions instead of inline on*= attributes" do
    erb_files = Dir.glob(Rails.root.join("app/views/**/*.erb"))
    handlers = FORBIDDEN_HANDLERS.join("|")

    # Three forms a view might emit a forbidden handler:
    #   1. Raw HTML attr:   <button onclick="...">
    #   2. Ruby symbol key: { onchange: "..." }
    #   3. Ruby rocket key: { :onchange => "..." } or { "onchange" => "..." }
    pattern = /
      (?:\b|:|['"])         # boundary, leading sigil colon, or opening quote
      (#{handlers})         # handler name
      ['"]?                  # optional closing quote for string keys
      \s*
      (?:=|:|=>)            # any of: HTML attr =, sym key :, rocket =>
      \s*
      ['"]                   # value's opening quote
    /ix

    violations = erb_files.each_with_object([]) do |path, acc|
      File.foreach(path).with_index(1) do |line, lineno|
        next unless line =~ pattern
        attr = Regexp.last_match(1)
        acc << "#{path.sub("#{Rails.root}/", '')}:#{lineno}  (#{attr})"
      end
    end

    expect(violations).to be_empty, <<~MSG
      Inline event handlers found in #{violations.size} location(s):

      #{violations.join("\n")}

      These are blocked by CSP in dev/prod. Replace with a Stimulus action:
        BAD:   onchange="this.form.requestSubmit()"
        GOOD:  data: { action: "change->search-form#submit" }
    MSG
  end
end
