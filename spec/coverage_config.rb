# frozen_string_literal: true

# Single source of truth for the coverage thresholds.
#
# These are read from two processes that never share a runtime: spec/rails_helper.rb
# (in-suite, single-process floor) and bin/parallel-rspec (which enforces the floor
# on the MERGED result of the parallel workers). They used to be literals in both
# with "keep in sync" comments on each — an admission that DRY had failed, in the
# files whose whole job is preventing exactly that kind of drift (#496).
#
# Deliberately dependency-free: bin/parallel-rspec require_relative's this before
# Rails exists, and it must stay loadable from a bare `ruby -e` collate subprocess.
# NOT under spec/support/, which rails_helper glob-requires only after Rails boots —
# too late for the SimpleCov.start block at the top of that file.
module CoverageConfig
  # Enforced on a single-process run, and on the merged result of a parallel run.
  MINIMUM = 40

  # Parallel workers each write a resultset; the collate step merges them. The
  # default 10-minute window is shorter than a full suite, which would silently
  # drop early workers from the merge and under-report coverage.
  MERGE_TIMEOUT = 3600
end
