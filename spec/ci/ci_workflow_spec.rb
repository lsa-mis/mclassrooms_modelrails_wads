require "rails_helper"
require "yaml"

RSpec.describe "the CI workflow" do
  let(:workflow) { YAML.safe_load_file(Rails.root.join(".github/workflows/ci.yml"), aliases: true) }
  let(:triggers) { workflow[true] || workflow["on"] }

  it "checks every pull request, and next and main again after every merge" do
    expect(triggers.keys).to contain_exactly("pull_request", "push")
    expect(triggers.dig("push", "branches")).to contain_exactly("next", "main")
  end

  it "gives every push its own run, so each merge keeps its own result" do
    expect(workflow.dig("concurrency", "group")).to eq("ci-${{ github.workflow }}-${{ github.head_ref || github.sha }}")
    expect(workflow.dig("concurrency", "cancel-in-progress")).to eq("${{ github.event_name == 'pull_request' }}")
  end

  it "has no workflow-level path filters, so required checks always report" do
    expect(triggers.dig("pull_request", "paths")).to be_nil
    expect(triggers.dig("pull_request", "paths-ignore")).to be_nil
  end

  describe "change lanes" do
    let(:jobs) { workflow["jobs"] }
    let(:full) { "needs.changes.outputs.full == 'true'" }

    def step_running(job, command)
      jobs.dig(job, "steps").find { |step| step["run"].to_s.include?(command) }
    end

    it "classifies only a pull request into next; a push, a release fix or a hotfix into main is full" do
      plan = step_running("changes", "bin/test-plan --github-output")
      everything_else = step_running("changes", "full=true")
      into_next = "github.event_name == 'pull_request' && github.base_ref == 'next'"

      expect(plan["run"]).to include('--base "origin/${BASE_REF}"')
      expect(plan["if"]).to eq(into_next)
      expect(everything_else["if"]).to eq("!(#{into_next})")
      expect(jobs.dig("changes", "outputs", "full"))
        .to include("steps.#{plan["id"]}.outputs.full", "steps.#{everything_else["id"]}.outputs.full")
    end

    it "classifies before bundle install, with the history the diff needs" do
      steps = jobs.dig("changes", "steps")
      ruby = steps.find { |step| step["uses"].to_s.start_with?("ruby/setup-ruby@") }
      checkout = steps.find { |step| step["uses"].to_s.start_with?("actions/checkout@") }

      expect(ruby.dig("with", "bundler-cache")).to be(false)
      expect(checkout.dig("with", "fetch-depth")).to eq(0)
    end

    it "shards run only for a full change" do
      expect(jobs.dig("split_seed", "if")).to eq(full)
      expect(jobs.dig("test_shard", "if")).to eq(full)
      expect(Array(jobs.dig("split_seed", "needs"))).to include("changes")
    end

    it "a lane change runs its specs with the same browser and assets as a shard" do
      lane = jobs["lane_specs"]
      runs = lane["steps"].map { |step| step["run"].to_s }

      expect(lane["if"]).to eq("needs.changes.outputs.full == 'false'")
      expect(step_running("lane_specs", "bin/test-plan --run")["run"]).to include('--base "origin/${BASE_REF}"')
      expect(runs).to include(match(/google-chrome --version/), match(%r{bin/rails assets:precompile}))
      expect(lane["steps"].find { |step| step["if"] == "failure()" }&.dig("with", "path")).to eq("tmp/capybara/")
    end

    it "test passes on whichever path ran, and fails if neither did" do
      test = jobs["test"]
      guard = test["steps"].first

      expect(Array(test["needs"])).to include("changes", "test_shard", "lane_specs")
      expect(guard["env"]).to include(
        "FULL" => "${{ needs.changes.outputs.full }}",
        "SHARDS" => "${{ needs.test_shard.result }}",
        "LANE" => "${{ needs.lane_specs.result }}"
      )
      expect(guard["run"]).to include('if [ "$FULL" = true ]; then want="$SHARDS"; else want="$LANE"; fi')
      expect(guard["run"]).to include("exit 1")
    end

    it "merges coverage and saves runtimes only after a full run" do
      merge_steps = jobs.dig("test", "steps").drop(1)

      expect(merge_steps).to all(satisfy { |step| step["if"].to_s.include?(full) })
    end
  end

  describe "system packages" do
    let(:steps) { workflow["jobs"].values.flat_map { |job| job["steps"].to_a } }
    let(:package_steps) { steps.select { |step| step["uses"] == "./.github/actions/apt-packages" } }
    let(:action) { YAML.safe_load_file(Rails.root.join(".github/actions/apt-packages/action.yml")) }
    let(:action_steps) { action.dig("runs", "steps") }

    it "come through the cached action, so an Ubuntu mirror outage doesn't fail every job" do
      expect(steps.map { |step| step["run"].to_s }.grep(/apt-get/)).to be_empty
      expect(package_steps.map { |step| step.dig("with", "packages") }).to contain_exactly(
        "libvips42t64", "libvips42t64 libheif-plugin-libde265", "libvips42t64 libheif-plugin-libde265"
      )
      expect(package_steps.map { |step| step["timeout-minutes"] }).to all(eq(5))
    end

    it "are restored before the mirror is asked, under a key that changes with the runner image" do
      uses = action_steps.map { |step| step["uses"].to_s.split("@").first }
      key = action_steps.find { |step| step["id"] == "key" }["run"]

      expect(uses.index("actions/cache/restore")).to be < action_steps.index { |step| step["run"].to_s.include?("apt-get update") }
      expect(key).to include("$ImageOS", "$ImageVersion", "$PACKAGES")
    end

    it "are saved only when the mirror supplied them" do
      save = action_steps.find { |step| step["uses"].to_s.start_with?("actions/cache/save@") }

      expect(save["if"]).to eq("steps.install.outputs.fetched == 'true'")
    end
  end
end
