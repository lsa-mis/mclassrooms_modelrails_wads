require "rails_helper"
require "tmpdir"

RSpec.describe ForkConfig do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = Pathname.new(dir)
      example.run
    end
  end

  def record(yaml) = @root.join(".fork.yml").write(yaml)
  def defaults = described_class.read(@root).tenancy_defaults

  it "has recorded nothing in the template, and something once bin/fork has run" do
    expect(described_class.read(@root)).not_to be_recorded

    record("name: my_app\n")

    expect(described_class.read(@root)).to be_recorded
  end

  it "has recorded nothing when .fork.yml holds no mapping" do
    record("just a sentence\n")

    expect(described_class.read(@root)).not_to be_recorded
    expect(described_class.read(@root).preset).to be_nil
  end

  it "reads the decisions bin/fork wrote" do
    record("name: my_app\nproduct_name: My App\npreset: none\ntemplate_url: git@github.com:someone/modelrails_base.git\n")
    config = described_class.read(@root)

    expect([ config.name, config.product_name, config.preset, config.template_url ])
      .to eq([ "my_app", "My App", "none", "git@github.com:someone/modelrails_base.git" ])
    expect(config.to_h).to include("name" => "my_app", "preset" => "none")
  end

  it "knows a preset the app would refuse to boot on" do
    expect(described_class::PRESETS).to contain_exactly("personal", "shared", "none")
  end

  describe "#tenancy_defaults" do
    it "makes a recorded shared preset the default, with the app's name as its slug" do
      record("name: my_app\npreset: shared\n")

      expect(defaults).to eq("WORKSPACE_ON_SIGNUP" => "shared", "TENANCY_SHARED_WORKSPACE_SLUG" => "my_app")
    end

    it "needs no slug for the other presets" do
      record("name: my_app\npreset: none\n")

      expect(defaults).to eq("WORKSPACE_ON_SIGNUP" => "none")
    end

    it "has none when the preset was left undecided" do
      record("name: my_app\n")

      expect(defaults).to be_empty
    end

    it "has none in the template, which records no fork" do
      expect(defaults).to be_empty
    end
  end

  describe ".tenancy_env" do
    before { record("name: my_app\npreset: shared\n") }

    it "takes the recorded preset when the environment sets none" do
      expect(described_class.tenancy_env(@root, env: {}, test: false))
        .to eq("WORKSPACE_ON_SIGNUP" => "shared", "TENANCY_SHARED_WORKSPACE_SLUG" => "my_app")
    end

    it "lets the environment override the record" do
      env = { "WORKSPACE_ON_SIGNUP" => "personal", "PATH" => "/bin" }

      expect(described_class.tenancy_env(@root, env:, test: false))
        .to eq("WORKSPACE_ON_SIGNUP" => "personal", "TENANCY_SHARED_WORKSPACE_SLUG" => "my_app")
    end

    # A fork's suite pins the template's default preset; following the record would fail hundreds of specs.
    it "ignores the record under test" do
      expect(described_class.tenancy_env(@root, env: {}, test: true)).to be_empty
    end
  end

  it "lets .fork.yml into the production image" do
    patterns = Rails.root.join(".dockerignore").readlines(chomp: true).grep_v(/\A\s*(#|\z)/)
    excluded = patterns.reduce(false) do |out, pattern|
      negated = pattern.start_with?("!")
      matches = File.fnmatch?(pattern.delete_prefix("!").delete_prefix("/"), ".fork.yml", File::FNM_DOTMATCH)
      matches ? !negated : out
    end

    expect(excluded).to be(false)
  end
end
