# frozen_string_literal: true

require "rails_helper"

# The WCAG 2.2 AAA teardown audit (spec/support/axe_accessibility.rb) is a
# project invariant, and it sat inert for months without failing anything
# (#912): a second `Capybara.reset_sessions!` after-hook in spec/support ran
# ahead of it, so every example was on about:blank by the time it looked. The
# runtime half of the guarantee is that file's after(:suite) gate; this is the
# static half, one legible failure per way of switching the audit off.
RSpec.describe "AAA teardown audit is always on" do
  it "has no per-example opt-out tag anywhere in spec/" do
    hits = Dir.glob(Rails.root.join("spec/**/*.rb")).reject { |file| file == __FILE__ }.select do |file|
      without_comments(File.read(file)).include?("skip_axe_hook")
    end

    expect(hits).to be_empty,
      "The teardown audit has no opt-out. A page that must render a pattern " \
      "deliberately wrong is fixed to render it right instead:\n  #{hits.join("\n  ")}"
  end

  it "resets Capybara sessions only where rspec-rails already does — never from spec/support" do
    hits = Dir.glob(Rails.root.join("spec/support/**/*.rb")).select do |file|
      without_comments(File.read(file)).include?("reset_sessions!")
    end

    expect(hits).to be_empty,
      "rspec-rails resets sessions in its own system-test teardown, after every " \
      "config-level after hook has run. A second reset registered here runs " \
      "before the audit and hands it about:blank (#912):\n  #{hits.join("\n  ")}"
  end

  # The devcontainer workflow is a provisioning check ("does the container
  # boot and run a spec"), not an accessibility run; it is the one place the
  # escape hatch is set on purpose.
  skip_axe_allowed = %w[.github/workflows/devcontainer.yml].freeze

  it "never sets SKIP_AXE in any workflow that runs specs, or in the pre-push hooks" do
    candidates = Dir.glob(Rails.root.join(".github/workflows/*.yml")) + [ Rails.root.join("lefthook.yml").to_s ]
    hits = candidates.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
      .reject { |path| skip_axe_allowed.include?(path) }
      .select { |path| File.read(Rails.root.join(path)).include?("SKIP_AXE") }

    expect(hits).to be_empty, "SKIP_AXE is a local focused-loop escape hatch only: #{hits.join(", ")}"
  end

  it "keeps the per-example audit and the suite gate registered, behind nothing but the SKIP_AXE guard" do
    source = without_comments(File.read(Rails.root.join("spec/support/axe_accessibility.rb")))
    configure = source[/^RSpec\.configure do \|config\|.*\z/m]

    expect(configure).to include("config.after(:each, type: :system) do |example|")
    expect(configure).to include("config.after(:suite) do")
    # A registration can be wrapped at the configure block's indentation or
    # one level in (inside the SKIP_AXE guard); both are scanned. The hook
    # bodies' own branches sit deeper and are not registrations.
    expect(configure.scan(/^ {2,4}(?:if|unless|case) .*$/)).to contain_exactly(a_string_including('unless ENV["SKIP_AXE"] == "1"'))
  end
end
