require "rails_helper"

# `bg-surface` is the PAGE. A bordered container painted with it is the same
# colour as the ground beneath it, so it reads as a bare outline rather than a
# card — and since the layout's `<body>` moved to `bg-surface` (PR #1191, the
# paired half of the gem's v0.19.0 surface ruling), that is exactly what two
# strays looked like: the activity feed and the join-policy section.
#
# The ruling, from modelrails_ui's docs/design-tokens.md:
#
#   * bg-surface-raised  — a card-shaped container that sits ON the page.
#   * bg-surface-overlay — a container that floats ABOVE it (dialog, popover,
#                          menu, tooltip surface).
#
# Ported from the gem's `test/test_container_surface.rb` (gem #210) so the app
# holds the same line as the library it vendors from. The gem's copy scores
# component class constants; this one scores the app's own views and components,
# which is where the strays were.
#
# DERIVED, not named: any class string that paints a bordered box is scored, so
# a new view picking `bg-surface` fails here rather than quietly adding a third
# answer. What this cannot see is a bordered box with no surface token at all —
# absence is not scored, only a wrong choice.
RSpec.describe "Code smell: a bordered container is never painted with the page surface" do
  # Methods rather than constants: a SCREAMING_CASE assignment inside a describe
  # block defines an Object-level constant, which this suite forbids
  # (spec/code_smells/no_object_level_spec_constants_spec.rb).
  def legal = %w[bg-surface-raised bg-surface-overlay]

  # `bg-surface-sunken` is a well — an inset area INSIDE a container, never the
  # container itself. `bg-surface` is the page.
  def illegal = %w[bg-surface bg-surface-sunken]

  def scanned_files
    Dir[Rails.root.join("app/views/**/*.erb")].sort +
      Dir[Rails.root.join("app/components/**/*.rb")].sort +
      Dir[Rails.root.join("app/components/**/*.erb")].sort
  end

  # The full token including any suffix, so `bg-surface-raised` is read as
  # itself rather than as `bg-surface` plus a hyphen — `\b` sits between "e" and
  # "-", so a bare /\bbg-surface\b/ matches inside every variant.
  #
  # The leading lookbehind rejects a VARIANT-PREFIXED token: `hover:bg-surface-sunken`
  # on a button is a pressed/hover state on a control, not the fill of a
  # container, and counting it flagged two buttons that are perfectly correct.
  # Only an unconditional fill paints the box.
  def surface_token(str) = str[/(?<![\w:.-])bg-surface(?:-[a-z]+)?\b/]

  # Quoted strings that paint a bordered box. A caller's opacity-modified token
  # (`bg-surface-sunken/40` on a table header) is a row fill inside a container,
  # not the container, and is deliberately not matched.
  def bordered_class_strings(src)
    src.scan(/"[^"]*"/m).select do |str|
      str.include?("border border-border") && surface_token(str)
    end
  end

  it "paints every bordered container with a container surface, never the page" do
    offenders = scanned_files.flat_map do |path|
      bordered_class_strings(File.read(path)).filter_map do |str|
        token = surface_token(str)
        next if legal.include?(token)
        next unless illegal.include?(token)

        "#{Pathname.new(path).relative_path_from(Rails.root)}: #{token}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      bordered containers painted with a non-container surface:
        #{offenders.join("\n  ")}

      Use bg-surface-raised (sits on the page) or bg-surface-overlay (floats
      above it). bg-surface is the page itself.
    MSG
  end

  # A guard that matches nothing passes for the wrong reason. This proves the
  # scan reaches real files with real bordered containers in them.
  it "actually scans bordered containers" do
    bordered = scanned_files.sum { |path| bordered_class_strings(File.read(path)).size }

    expect(bordered).to be > 5, "the derivation found almost no bordered containers — the match must have drifted"
  end
end
