class SyncRun < ApplicationRecord
  include Tenanted

  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }

  has_many :sync_phases, dependent: :destroy

  # Phase 8's admin UI shows the most recently started run. started_at is
  # only set once the pipeline begins executing phases, so a run created but
  # not yet started falls back to created_at (always present) for ordering.
  def self.latest
    order(Arel.sql("COALESCE(started_at, created_at) DESC")).first
  end
end
