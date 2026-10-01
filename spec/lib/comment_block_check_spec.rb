require "rails_helper"
require "comment_block_check"

RSpec.describe CommentBlockCheck do
  def violations(source, path:, added:)
    described_class.new.violations(path: path, source: source, added_lines: added)
  end

  def ruby_comment(lines) = Array.new(lines) { |i| "# line #{i + 1}" }.join("\n") + "\ndef x; end\n"

  # conventions.md rule 3: a one-line gist plus a pointer, so two lines at most.
  it "fails a new comment block longer than two lines" do
    expect(violations(ruby_comment(3), path: "app/models/x.rb", added: 1..3)).to eq([ 1..3 ])
  end

  it "passes a gist and a pointer line" do
    expect(violations(ruby_comment(2), path: "app/models/x.rb", added: 1..2)).to be_empty
  end

  # The failure this exists for is accretion: each review round appends a line
  # to a block that was fine when written.
  it "fails an existing block that an added line pushes past the limit" do
    expect(violations(ruby_comment(3), path: "app/models/x.rb", added: [ 3 ])).to eq([ 1..3 ])
  end

  it "leaves an untouched long block alone" do
    expect(violations(ruby_comment(9) + "y = 1\n", path: "app/models/x.rb", added: [ 11 ])).to be_empty
  end

  it "does not count functional comments as prose" do
    source = "# frozen_string_literal: true\n# rubocop:disable Foo\n" + ruby_comment(2)
    expect(violations(source, path: "app/models/x.rb", added: 1..4)).to be_empty
  end

  # A heredoc line opening with interpolation is code, and must not merge into a block.
  it "does not read a heredoc interpolation line as a comment" do
    source = [ "msg = <<~M", '  #{a}', '  #{b}', '  #{c}', "M" ].join("\n") + "\n"
    expect(violations(source, path: "spec/x_spec.rb", added: 1..5)).to be_empty
  end

  it "reads a multi-line ERB comment as one block, and skips strict locals" do
    erb = "<%# locals: (a:) -%>\n<%# one\n    two\n    three\n    four\n    five\n    six\n    seven %>\n<p>x</p>\n"
    expect(violations(erb, path: "app/views/x/_y.html.erb", added: 1..9)).to eq([ 2..8 ])
  end

  it "reads JS and CSS block comments" do
    js = "/*\n a\n b\n c\n d\n e\n*/\nconst x = 1\n"
    expect(violations(js, path: "app/javascript/app_owned.js", added: 1..8)).to eq([ 1..7 ])
    css = "/* a\n b\n c\n d\n e\n f\n g */\n.x {}\n"
    expect(violations(css, path: "app/assets/tailwind/x.css", added: 1..8)).to eq([ 1..7 ])
  end

  it "skips files the gem vendors, which regenerate from the gem" do
    expect(violations(ruby_comment(9), path: "app/components/ui/button_component.rb", added: 1..9)).to be_empty
  end

  # A preview's comments are the notes Lookbook renders, not commentary on code.
  it "skips Lookbook preview classes, whose comments render as notes" do
    expect(violations(ruby_comment(9), path: "spec/components/previews/ui/skeleton_component_preview.rb", added: 1..9)).to be_empty
    erb = "<%# one\n    two\n    three %>\n<p>x</p>\n"
    expect(violations(erb, path: "spec/components/previews/ui/skeleton_component_preview/default.html.erb", added: 1..3)).to eq([ 1..3 ])
  end

  describe ".added_lines" do
    it "reads the new-side line numbers from a zero-context diff" do
      diff = "@@ -3,0 +4,3 @@\n+a\n+b\n+c\n@@ -10 +13 @@\n-x\n+y\n@@ -20,2 +22,0 @@\n-p\n-q\n"

      expect(described_class.added_lines(diff)).to eq([ 4, 5, 6, 13 ])
    end
  end

  # POSITIVE CONTROL for the gem-derived set: if it came back empty, every
  # vendored controller would be checked and regenerations would fail.
  it "recognises a controller the installed gem vendors, and not an app-owned one" do
    check = described_class.new

    expect(check.violations(path: "app/javascript/controllers/form_draft_controller.js",
                            source: "//\n" * 9, added_lines: 1..9)).to be_empty
    expect(check.violations(path: "app/javascript/controllers/theme_controller.js",
                            source: "//\n" * 9, added_lines: 1..9)).to eq([ 1..9 ])
  end

  it "ignores file types it does not parse" do
    expect(violations(ruby_comment(9), path: "app/docs/developer/x.md", added: 1..9)).to be_empty
  end
end
