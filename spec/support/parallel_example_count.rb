# Each parallel worker records how many examples it actually ran so
# bin/parallel-rspec can verify the splitter neither dropped nor duplicated a
# spec file (executed sum must equal the dry-run enumeration). Registered only
# under parallel_tests — TEST_ENV_NUMBER is set there ("" for worker 1) — so
# plain `bundle exec rspec` is unaffected.
class ParallelExampleCountFormatter
  RSpec::Core::Formatters.register self, :dump_summary

  def self.counts_dir
    Rails.root.join("tmp/parallel_example_counts")
  end

  def initialize(_output); end

  def dump_summary(summary)
    dir = self.class.counts_dir
    FileUtils.mkdir_p(dir)
    worker = ENV["TEST_ENV_NUMBER"].to_s.empty? ? "1" : ENV["TEST_ENV_NUMBER"]
    File.write(dir.join("#{worker}.count"), summary.example_count.to_s)
  end
end

RSpec.configure do |config|
  unless ENV["TEST_ENV_NUMBER"].nil?
    # add_formatter replaces RSpec's implicit default formatter, so restore
    # progress output first (parallel_tests reads worker summaries from it)
    # unless the CLI already chose a formatter.
    config.add_formatter :progress if config.formatters.empty?
    config.add_formatter ParallelExampleCountFormatter
  end
end
