# Records per-file spec runtimes so the NEXT parallel run can split work by
# measured time instead of file size — evening out the slowest worker (the
# file-size split left one CI worker ~1.5 min behind the pack, #488).
#
# parallel_tests reads tmp/parallel_runtime_rspec.log at split time with NO
# --group-by flag on bin/parallel-rspec: it uses runtime grouping only when the
# log covers enough files and silently falls back to file size otherwise, so a
# missing or cold log (first run, CI cache miss) can never break the split.
# Registered only under parallel_tests (TEST_ENV_NUMBER set) so plain
# `bundle exec rspec` is unaffected.
require "parallel_tests/rspec/runtime_logger"

RSpec.configure do |config|
  unless ENV["TEST_ENV_NUMBER"].nil?
    # add_formatter replaces RSpec's implicit default formatter, so ensure the
    # progress formatter survives (parallel_tests parses worker progress output)
    # before adding the non-default runtime logger. Independent of support-file
    # load order — harmless if progress was already restored elsewhere.
    config.add_formatter :progress if config.formatters.empty?
    config.add_formatter ParallelTests::RSpec::RuntimeLogger,
                         Rails.root.join("tmp/parallel_runtime_rspec.log").to_s
  end
end
