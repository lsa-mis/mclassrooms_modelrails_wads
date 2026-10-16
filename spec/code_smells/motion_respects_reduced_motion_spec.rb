# frozen_string_literal: true

require "rails_helper"

# WCAG 2.3.3 (AAA): a utility that moves something is written `motion-safe:`, so
# Reduce Motion turns it off. Ported from modelrails_ui#266; the why is in the doc.
RSpec.describe "Code smell: motion respects Reduce Motion" do
  let(:roots) { %w[app/components app/views app/javascript app/assets/tailwind spec/components/previews] }
  let(:files) { roots.flat_map { |root| Dir[Rails.root.join(root, "**/*.{rb,erb,js,css}")] }.sort }
  let(:files_written_against) { 761 }

  # transition-colors / -opacity / -shadow do not move anything and stay bare.
  let(:motion) { /(?<=["'`\s])(transition|transition-all|transition-transform|animate-[a-z0-9-]+)(?=["'`\s]|\z)/ }
  let(:comment_line) { %r{\A\s*(#|//|\*|/\*|<%#)} }
  let(:arbitrary_transition) { /(?<=["'`\s])transition-\[([^\]]+)\](?=["'`\s]|\z)/ }
  # A transition-[…] list moves something unless every property in it only repaints.
  let(:repaint_properties) { %w[color background-color border-color outline-color text-decoration-color fill stroke opacity box-shadow] }

  def motion_tokens(line)
    arbitrary = line.scan(arbitrary_transition).flatten.reject { |list| (list.split(",") - repaint_properties).empty? }
    line.scan(motion).flatten + arbitrary.map { |list| "transition-[#{list}]" }
  end

  # 2.3.3 exempts motion essential to what is conveyed. Each entry is a decision
  # with its reason, not a way to quiet the check.
  let(:essential) do
    {
      "app/components/ui/spinner_component.rb animate-spin" =>
        "the spin is the busy signal; a still spinner conveys nothing",
      "spec/components/previews/ui/spinner_component_preview/dont_no_status_text.html.erb animate-spin" =>
        "the same spinner, hand-rolled to show what it looks like without its status text"
    }
  end

  def bare_motion(path)
    relative = path.delete_prefix("#{Rails.root}/")
    File.readlines(path).each_with_index.flat_map do |line, index|
      next [] if line.match?(comment_line)

      motion_tokens(line).map { |token| [ "#{relative} #{token}", "#{relative}:#{index + 1} #{token}" ] }
    end
  end

  def all_bare_motion = files.flat_map { |path| bare_motion(path) }

  it "reads the tree it was written against (floor)" do
    expect(files.size).to be >= files_written_against
  end

  it "recognises a bare motion utility and lets a guarded one through (positive control)" do
    sample = %(class: "p-2 transition-all animate-spin motion-safe:transition-transform transition-colors transition ) +
             %(transition-[width] transition-[opacity,color] motion-safe:transition-[height]")
    expect(motion_tokens(sample)).to eq(%w[transition-all animate-spin transition transition-[width]])
  end

  it "moves nothing outside motion-safe" do
    offenders = all_bare_motion.reject { |key, _| essential.key?(key) }.map(&:last)

    expect(offenders).to be_empty, <<~MSG
      These utilities animate transform, so they move something on screen, and they are
      not behind `motion-safe:`. Someone who has asked their OS to reduce motion gets it
      anyway (WCAG 2.3.3). Write them `motion-safe:<utility>`; if only colour or opacity
      changes, `transition-colors` / `transition-opacity` is the honest class and needs no
      prefix:
        #{offenders.join("\n  ")}
    MSG
  end

  it "keeps every essential exemption matching a real site" do
    stale = essential.keys - all_bare_motion.map(&:first)

    expect(stale).to be_empty, "remove essential entries that no longer match a bare motion utility: #{stale.join(', ')}"
  end
end
