RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Limit a run to :focus-tagged examples/groups (fit/fdescribe/fcontext);
  # when nothing is tagged, everything runs.
  config.filter_run_when_matching :focus

  # Persist example status so `--only-failures` / `--next-failure` work. Under
  # parallel_tests each worker writes its own file (TEST_ENV_NUMBER) so a
  # shared path can't be clobbered; kept under tmp/ (gitignored).
  config.example_status_persistence_file_path = "tmp/rspec_status#{ENV.fetch('TEST_ENV_NUMBER', '')}.txt"

  # Verbose (documentation) output when running a single file.
  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  # Run specs in random order to surface order dependencies, seeding the
  # process PRNG from the run seed so a failing `--seed NNNN` reproduces the
  # exact interleaving (and Faker sequence). Re-enabled once #456's order-
  # dependent flake (a workspace-scoped-slug collision) was fixed — see #493.
  config.order = :random
  Kernel.srand config.seed
end
