require "rails_helper"
require "tmpdir"

RSpec.describe Vocabulary do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  let(:defaults) { dir.join("vocabulary.yml") }
  let(:override) { dir.join("vocabulary.local.yml") }

  after do
    FileUtils.rm_rf(dir)
    described_class.reload!
  end

  def write_defaults
    defaults.write(<<~YAML)
      workspace: { singular: "workspace", plural: "workspaces" }
      project:   { singular: "project",   plural: "projects" }
    YAML
  end

  it "derives the eight tokens from two stored forms per noun" do
    write_defaults

    tokens = described_class.reload!(defaults: defaults, override: override)

    expect(tokens).to eq(
      workspace: "workspace", workspaces: "workspaces", Workspace: "Workspace", Workspaces: "Workspaces",
      project: "project", projects: "projects", Project: "Project", Projects: "Projects"
    )
  end

  it "lets a fork override any subset and keeps the template's defaults for the rest" do
    write_defaults
    override.write(%(workspace: { singular: "course", plural: "courses" }\n))

    tokens = described_class.reload!(defaults: defaults, override: override)

    expect(tokens.values_at(:workspace, :Workspaces, :project)).to eq([ "course", "Courses", "project" ])
  end

  it "works with no override file at all" do
    write_defaults

    expect(described_class.reload!(defaults: defaults, override: override)[:workspace]).to eq("workspace")
  end

  it "is frozen, so nothing request-scoped can mutate it" do
    write_defaults

    expect(described_class.reload!(defaults: defaults, override: override)).to be_frozen
  end

  it "names the file when the DEFAULTS are malformed" do
    defaults.write(<<~YAML)
      workspace: { singular: "", plural: "workspaces" }
      project:   { singular: "project", plural: "projects" }
    YAML

    expect { described_class.reload!(defaults: defaults, override: override) }
      .to raise_error(Vocabulary::InvalidVocabulary, /vocabulary\.yml.*workspace.*singular/)
  end

  it "names the file and the noun when an override is malformed" do
    write_defaults
    override.write(%(workspace: "course"\n))

    expect { described_class.reload!(defaults: defaults, override: override) }
      .to raise_error(Vocabulary::InvalidVocabulary, /vocabulary\.local\.yml.*workspace.*singular/)
  end

  it "names the file when its YAML is not a mapping" do
    write_defaults
    override.write("just a string\n")

    expect { described_class.reload!(defaults: defaults, override: override) }
      .to raise_error(Vocabulary::InvalidVocabulary, /vocabulary\.local\.yml: expected a mapping of nouns/)
  end

  it "refuses a noun the template does not know" do
    write_defaults
    override.write(%(member: { singular: "student", plural: "students" }\n))

    expect { described_class.reload!(defaults: defaults, override: override) }
      .to raise_error(Vocabulary::InvalidVocabulary, /member/)
  end

  it "loads the shipped defaults at boot" do
    # Whatever the host's real files say, not the template's literal words —
    # a renamed fork's shipped defaults are its own words, and the boot memo
    # must equal a fresh read of them either way.
    expect(described_class.tokens).to eq(described_class.reload!)
  end
end
