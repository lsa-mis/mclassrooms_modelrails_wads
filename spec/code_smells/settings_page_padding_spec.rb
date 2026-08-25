require "rails_helper"

# app/views/layouts/settings.html.erb's shared <main> carries no vertical
# padding of its own (by design — see the 2026-07-02 header-spacing design
# review). Every settings page must supply exactly one top-padding source:
# either the shared .page-container/.page-container-wide class (which both
# carry padding-block: var(--space-section-gap)), or its own explicit
# py-*/pt-* utility for pages whose width doesn't match either named class.
#
# The historical bug this guards against: the layout USED to hardcode its
# own py-8, and pages ALSO added their own py-16/py-8 on top, silently
# compounding to 64-96px effective (all 8 settings pages, caught by eye
# during design review, not CI). This spec keeps both failure directions —
# zero sources (page floats flush under the header) and two sources
# (compounding) — caught by CI going forward.
RSpec.describe "Settings page top-level padding" do
  let(:settings_view_files) do
    Dir[Rails.root.join("app/views/settings/**/*.html.erb")].reject { |f| File.basename(f).start_with?("_") }
  end

  def top_level_wrapper(content)
    content[/<(?:div|section)\b[^>]*class="[^"]*"/m]
  end

  it "supplies exactly one vertical-padding source per page (never zero, never two)" do
    violations = settings_view_files.filter_map do |file|
      wrapper = top_level_wrapper(File.read(file))
      next "#{file}: no top-level <div>/<section> with a class found" unless wrapper

      classes = wrapper[/class="[^"]*"/]
      uses_named_class = classes.match?(/\bpage-container(?:-wide)?\b/)
      has_own_padding = classes.match?(/\bp[ty]?-\d+\b/)

      relative = file.delete_prefix("#{Rails.root}/")
      if uses_named_class && has_own_padding
        "#{relative}: uses page-container AND its own py-*/pt-* — compounds (#{classes})"
      elsif !uses_named_class && !has_own_padding
        "#{relative}: no page-container class and no py-*/pt-* — page floats flush under the header (#{classes})"
      end
    end

    expect(violations).to be_empty,
      "expected every settings page's top-level wrapper to have EXACTLY ONE vertical-padding " \
      "source (the page-container/-wide class, or its own py-*/pt-* if the page's width " \
      "doesn't match either class). Found:\n#{violations.join("\n")}"
  end

  # #692: the settings column must hold ONE width across the sidebar
  # click-through — hand-rolled max-w-* wrappers made it jump 448→672→768px
  # per click. Width comes from the shared container classes only.
  it "takes page width from page-container/-wide, never a hand-rolled max-w-*" do
    violations = settings_view_files.filter_map do |file|
      wrapper = top_level_wrapper(File.read(file))
      next unless wrapper

      classes = wrapper[/class="[^"]*"/]
      next if classes.match?(/\bpage-container(?:-wide)?\b/)

      "#{file.delete_prefix("#{Rails.root}/")}: #{classes}" if classes.match?(/\bmax-w-\w+\b/)
    end

    expect(violations).to be_empty,
      "settings pages sizing themselves outside .page-container/-wide:\n#{violations.join("\n")}"
  end
end
