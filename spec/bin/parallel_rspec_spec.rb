require "rails_helper"

# `load` defines the class without running it (bottom-of-file guard), matching
# the bin/deploy-guide spec's pattern of exercising bin scripts directly.
load Rails.root.join("bin/parallel-rspec")

RSpec.describe ParallelRspecRunner do
  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:counts_dir) { workdir.join("counts") }
  let(:dry_run_json) { workdir.join("dry_run.json") }
  let(:runner) { described_class.new(counts_dir: counts_dir, dry_run_json: dry_run_json) }

  after { FileUtils.remove_entry(workdir) }

  def write_counts(counts_by_worker)
    FileUtils.mkdir_p(counts_dir)
    counts_by_worker.each { |worker, count| counts_dir.join("#{worker}.count").write(count.to_s) }
  end

  def write_dry_run(example_count)
    FileUtils.mkdir_p(dry_run_json.dirname)
    dry_run_json.write({ summary: { example_count: example_count } }.to_json)
  end

  describe "#expected_count" do
    it "reads the example count from the dry-run JSON" do
      write_dry_run(3502)
      expect(runner.expected_count).to eq(3502)
    end
  end

  describe "#executed_count" do
    it "sums every worker's count file" do
      write_counts("1" => 900, "2" => 880, "3" => 872, "4" => 850)
      expect(runner.executed_count).to eq(3502)
    end
  end

  describe "#verify_count!" do
    it "passes silently when executed matches expected" do
      write_dry_run(10)
      write_counts("1" => 4, "2" => 6)
      expect { runner.verify_count! }.not_to raise_error
    end

    it "aborts with a diagnostic when an example went missing" do
      write_dry_run(10)
      write_counts("1" => 4, "2" => 5)
      expect { runner.verify_count! }.to raise_error(SystemExit) do |error|
        expect(error.status).not_to eq(0)
      end
    end
  end
end
