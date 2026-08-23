require "rails_helper"

# Suite-wide phantom-class guard for the btn-* utility family (#682): Tailwind
# emits only classes it knows, so a typo'd or renamed btn-* utility ships as
# silently unstyled markup. Every btn-* token used in views/components must
# resolve to a real rule selector in the compiled build. .btn-secondary is the
# positive control on both sides — if the extractor or the CSS parser stops
# finding IT, the probe is broken, not the code.
# CI is authoritative: builds/ is gitignored, so a stale local build can pass
# this vacuously — only CI's fresh assets:precompile proves a negative. Scope
# is the btn-* family only; other utility families (e.g. signal borders) are
# not covered here.
RSpec.describe "button utilities in compiled Tailwind" do
  before do
    skip "run bin/rails tailwind:build first" unless build_css_path.exist?
  end

  def build_css_path
    Rails.root.join("app/assets/builds/tailwind.css")
  end

  def css
    @css ||= build_css_path.read
  end

  # Every btn-* class token referenced by app markup. The lookbehind keeps
  # foreign namespaces (e.g. biscuit-btn--*) out of the btn-* family.
  def used_tokens
    files = Dir[Rails.root.join("app/views/**/*.erb")] +
      Dir[Rails.root.join("app/components/**/*.{rb,erb}")]
    files.flat_map { |f| File.read(f).scan(/(?<![\w-])btn-[a-z][a-z-]*[a-z]/) }.uniq.sort
  end

  # Class names that appear in actual rule selectors (escape-aware): take the
  # selector text preceding each `{`, drop at-rules, unescape `\x` sequences.
  def compiled_selector_classes
    @compiled_selector_classes ||= css
      .scan(/([^{};]+)\{/)
      .flatten
      .reject { |selector| selector.lstrip.start_with?("@") }
      .flat_map { |selector| selector.scan(/\.((?:[\w-]|\\.)+)/) }
      .flatten
      .map { |name| name.gsub(/\\(.)/, '\1') }
      .to_set
  end

  # Union of the declaration bodies of every rule whose selector list mentions
  # `.<class_name>` (the minified build splits one utility across several
  # blocks: base, :focus-visible, color layer, sizing layer).
  def declarations_for(class_name)
    css.scan(/[^{};]*\.#{Regexp.escape(class_name)}(?![\w-])[^{};]*\{([^{}]*)\}/)
      .flatten.join(";")
  end

  it "finds no phantom btn-* tokens in views or components" do
    expect(used_tokens).to include("btn-secondary") # positive control: extractor
    expect(compiled_selector_classes).to include("btn-secondary") # positive control: parser

    phantoms = used_tokens.reject { |token| compiled_selector_classes.include?(token) }
    expect(phantoms).to be_empty,
      "btn-* classes used in markup but absent from the compiled build: #{phantoms.join(', ')}"
  end

  it "compiles .btn-outline-primary with the interactive token" do
    expect(declarations_for("btn-outline-primary")).to include("--color-interactive")
  end

  it "keeps the 44px AAA min-width floor on the filled family and outline sibling" do
    expect(declarations_for("btn-touch-target")).to include("min-width:var(--form-input-height)") # positive control

    %w[btn-primary btn-secondary btn-danger btn-outline-primary].each do |name|
      expect(declarations_for(name)).to include("min-width:var(--form-input-height)"),
        ".#{name} lost the min-width target floor"
    end
  end
end
