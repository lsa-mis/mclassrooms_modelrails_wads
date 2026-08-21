# frozen_string_literal: true

require "rails_helper"

# A DOM id baked into a constant is a duplicate-id bug waiting for the second instance.
# Components are reusable by definition, so the moment a page renders two of them the
# shared id collides — and the ARIA that points AT it (`aria-controls`,
# `aria-labelledby`, `aria-activedescendant`) silently resolves to whichever element
# rendered first. Assistive tech then describes the wrong node, and nothing in a
# single-instance preview or spec reveals it.
#
# This has now bitten twice: `UI::Combobox` (LIST_ID = "combobox-list") and
# `UI::Command` (LIST_ID = "command-list"). Second occurrence of a class means a guard,
# not a third fix.
#
# The rule: derive ids from a per-instance value (`@id`, itself defaulting to
# `SecureRandom.hex`), never from a constant or a bare literal.
RSpec.describe "Code smell: no constant DOM ids in components" do
  # A constant whose name reads like an element id, assigned a plain string.
  let(:constant_id) { /^\s*[A-Z][A-Z0-9_]*_?ID\s*=\s*["']/ }

  it "defines no *_ID constant holding a literal string" do
    offenders = Rails.root.glob("app/components/**/*.rb").filter_map do |path|
      hits = path.read.lines.each_with_index.filter_map do |line, i|
        "#{path.relative_path_from(Rails.root)}:#{i + 1}: #{line.strip}" if line.match?(constant_id)
      end
      hits if hits.any?
    end.flatten

    expect(offenders).to be_empty, <<~MSG
      Constant DOM ids collide as soon as a page renders two of the component.
      Derive from a per-instance id instead:

        @id = html_attrs.delete(:id) || "thing-\#{SecureRandom.hex(4)}"
        def list_id = "\#{@id}-list"

      #{offenders.join("\n")}
    MSG
  end

  # The runtime half of the same bug: a Stimulus controller minting ids from a fixed
  # prefix restarts its counter per controller instance, so two on a page produce the
  # same ids. Seed the prefix from the element's own id.
  it "mints no runtime element ids from a hardcoded prefix" do
    offenders = Rails.root.glob("app/javascript/controllers/*.js").filter_map do |path|
      hits = path.read.lines.each_with_index.filter_map do |line, i|
        next unless line.match?(/\.id\s*=\s*`[a-z][a-z-]*-\$\{/)

        "#{path.relative_path_from(Rails.root)}:#{i + 1}: #{line.strip}"
      end
      hits if hits.any?
    end.flatten

    expect(offenders).to be_empty, <<~MSG
      Runtime ids built from a literal prefix collide across controller instances.
      Seed the prefix from the host element's id, which is already unique.

      #{offenders.join("\n")}
    MSG
  end
end
