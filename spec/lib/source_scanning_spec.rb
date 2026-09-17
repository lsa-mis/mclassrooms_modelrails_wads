# frozen_string_literal: true

require "rails_helper"

# The old hand-rolled quote scanner tracked ' and " state per LINE, so a
# heredoc body line (no opening quote of its own) had a `#{...}`
# interpolation's `#` read as a comment start and everything after it
# deleted — silently truncating code the code-smell fences then couldn't see
# (spec/code_smells/axe_teardown_audit_is_always_on_spec.rb scans spec/ with
# this helper). Prism-based blanking replaces the quote scanner entirely.
RSpec.describe "SourceScanning#without_comments" do
  include SourceScanning

  it "blanks a trailing comment" do
    result = without_comments(%(foo = 1 # a real comment\n))
    expect(result).to include("foo = 1")
    expect(result).not_to include("a real comment")
  end

  it "blanks a full-line comment without losing the line below it" do
    result = without_comments(%(# just a comment\nfoo = 1\n))
    expect(result.lines[0]).not_to include("just a comment")
    expect(result.lines[1]).to eq("foo = 1\n")
  end

  it "leaves a \#{} interpolation inside a heredoc body untouched" do
    source = <<~RUBY
      cdp_evaluate(<<~JS)
        document.querySelectorAll(\#{data_table_row_sel.to_json})
      JS
    RUBY
    expect(without_comments(source)).to include("data_table_row_sel.to_json")
  end

  it "preserves line count so reported line numbers stay accurate" do
    source = "a # x\nb\nc # y\n"
    expect(without_comments(source).lines.size).to eq(source.lines.size)
  end

  # This helper also scans .erb templates (spec/code_smells/
  # one_preferences_creation_path_spec.rb), which are not valid standalone
  # Ruby. Prism does not recover on ERB — Prism.parse reports errors, and
  # without_comments falls back to the old per-line quote scanner rather
  # than raising.
  it "still blanks a real comment on source that isn't valid Ruby on its own" do
    result = without_comments(%(<div><%= foo %></div> # trailing comment\n))
    expect(result).not_to include("trailing comment")
  end

  # Prism finds zero comments on this input (it's not valid Ruby, so it
  # never gets far enough to record one) — blank_comments would strip
  # nothing. Only the fallback's naive "first unquoted #" scan removes the
  # ERB comment tag, so this fails if without_comments ever took the Prism
  # branch here instead.
  it "blanks an ERB comment tag by taking the fallback scanner, not the Prism branch" do
    result = without_comments("<%# private note %>\nfoo = 1\n")
    expect(result).not_to include("private note")
    expect(result.lines[1]).to eq("foo = 1\n")
  end
end
