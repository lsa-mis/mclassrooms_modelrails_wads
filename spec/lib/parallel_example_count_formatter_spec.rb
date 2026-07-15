require "rails_helper"

RSpec.describe ParallelExampleCountFormatter do
  # Redirect writes to a temp dir: this spec itself runs inside a parallel
  # worker, and writing to the real counts dir would clobber a sibling
  # worker's count and trip bin/parallel-rspec's parity gate.
  let(:tmp_counts_dir) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.remove_entry(tmp_counts_dir) }

  def summary_with(example_count:)
    RSpec::Core::Notifications::SummaryNotification.new(
      1.0, Array.new(example_count), [], [], 0.1, 0
    )
  end

  it "writes this worker's executed example count to its counts file" do
    allow(described_class).to receive(:counts_dir).and_return(tmp_counts_dir)
    original = ENV["TEST_ENV_NUMBER"]
    ENV["TEST_ENV_NUMBER"] = "3"

    described_class.new(nil).dump_summary(summary_with(example_count: 7))

    expect(tmp_counts_dir.join("3.count").read).to eq("7")
  ensure
    original.nil? ? ENV.delete("TEST_ENV_NUMBER") : ENV["TEST_ENV_NUMBER"] = original
  end

  it "names worker 1's file '1' (its TEST_ENV_NUMBER is the empty string)" do
    allow(described_class).to receive(:counts_dir).and_return(tmp_counts_dir)
    original = ENV["TEST_ENV_NUMBER"]
    ENV["TEST_ENV_NUMBER"] = ""

    described_class.new(nil).dump_summary(summary_with(example_count: 5))

    expect(tmp_counts_dir.join("1.count").read).to eq("5")
  ensure
    original.nil? ? ENV.delete("TEST_ENV_NUMBER") : ENV["TEST_ENV_NUMBER"] = original
  end
end
