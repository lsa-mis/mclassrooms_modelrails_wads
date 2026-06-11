# frozen_string_literal: true

require "rails_helper"

# Guards the Lookbook Pages (the Overview landing + the "choosing" decision pages).
# Static source analysis only — same idiom as logical_path_coverage_spec.rb and
# scenario_grouping_spec.rb (read files, scan, assert; no render).
#
# Lookbook is a development-only gem (undefined in the test env), so we cannot resolve
# embeds through Lookbook::Engine.previews here. Instead we enforce the convention that
# GUARANTEES an embed resolves under the catalog-wide @!group grouping:
#
#   `@!group Overview/Examples/Reference` nests every leaf scenario inside a group, so a
#   GROUPED preview's top-level scenarios become the GROUP names. `embed UI::FooComponentPreview, :basic`
#   then resolves to nil (":basic" is a nested leaf, not a top-level scenario) and the page
#   raises ActionView::Template::Error. (A flat/ungrouped preview WOULD resolve a named leaf —
#   but pages mix both, so the scenario-less form is enforced uniformly as the one rule that
#   always resolves.) The safe, universal form is a scenario-less `embed UI::FooComponentPreview`,
#   which renders the preview's default scenario.
#
# See docs/superpowers/specs/2026-06-11-lookbook-tier3-completion-design.md.
RSpec.describe "Lookbook Pages" do
  preview_root = Rails.root.join("spec/components/previews/ui")
  pages_root = Rails.root.join("spec/components/previews/pages")

  scenario_defs = ->(src) { src.scan(/^\s+def ([a-z_][a-z0-9_]*)/).flatten - %w[input_attrs] }

  Dir.glob(pages_root.join("**/*.md.erb")).sort.each do |page|
    rel = page.sub("#{Rails.root}/", "")
    src = File.read(page)
    embeds = src.scan(/embed\s+(UI::\w+ComponentPreview)(\s*,\s*:\w+)?/)

    it "#{rel}: every embed uses the resolvable scenario-less form" do
      offenders = embeds.select { |_klass, scenario_arg| scenario_arg }.map(&:first).uniq
      expect(offenders).to be_empty,
        "grouping nests leaves, so `embed Klass, :leaf` resolves nil — drop the scenario arg: #{offenders.join(", ")}"
    end

    it "#{rel}: every embedded preview exists and has a default scenario" do
      embeds.each do |klass, _|
        file = klass.sub(/\AUI::/, "").sub(/ComponentPreview\z/, "").underscore
        preview_file = preview_root.join("#{file}_component_preview.rb")
        expect(File).to exist(preview_file), "#{klass}: no preview file at #{file}_component_preview.rb"
        expect(scenario_defs.call(File.read(preview_file))).not_to be_empty,
          "#{klass}: no scenario methods, so no default scenario to embed"
      end
    end
  end

  describe "the choosing decision pages" do
    # Filename → @logical_path section. Layout and Actions get no decision page by
    # design (too little sibling overlap); this map is the allowlist. 00_overview.md.erb
    # is a cross-section landing, deliberately outside it (the embed rules above still
    # cover it).
    section_by_page = {
      "choosing/00_forms.md.erb" => "Forms & Inputs",
      "choosing/01_overlays.md.erb" => "Overlays",
      "choosing/02_navigation.md.erb" => "Navigation",
      "choosing/03_feedback.md.erb" => "Feedback & Status",
      "choosing/04_data_display.md.erb" => "Data Display",
      "choosing/05_media.md.erb" => "Media"
    }

    it "maps every choosing page file to a section (no unmapped strays)" do
      actual = Dir.glob(pages_root.join("choosing/*.md.erb")).map { |p| p.sub("#{pages_root}/", "") }.sort
      expect(actual).to eq(section_by_page.keys.sort)
    end

    section_by_page.each do |rel, section|
      page_path = pages_root.join(rel)
      source = File.exist?(page_path) ? File.read(page_path) : ""

      siblings = Dir.glob(preview_root.join("*_component_preview.rb")).select do |path|
        File.read(path).match?(/^\s*#\s*@logical_path\s+#{Regexp.escape(section)}\s*$/)
      end.map { |path| File.basename(path, "_component_preview.rb") }.sort

      it "#{rel} routes every #{section} sibling" do
        expect(siblings).not_to be_empty
        # Match the backtick-delimited token, not a bare substring: otherwise `dialog`
        # would be falsely "covered" by `alert_dialog` and a dropped row would slip through.
        missing = siblings.reject { |name| source.match?(/`#{Regexp.escape(name)}`/) }
        expect(missing).to be_empty, "#{rel} is missing: #{missing.join(", ")}"
      end

      it "#{rel} embeds at least one live scenario per fork" do
        expect(source.scan(/embed\s+UI::\w+ComponentPreview/).size).to be >= 3
      end
    end
  end
end
