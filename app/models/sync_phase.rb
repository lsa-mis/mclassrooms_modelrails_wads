class SyncPhase < ApplicationRecord
  include Tenanted

  # Reference list of phase keys the pipeline (phase 2) writes: "campuses",
  # "buildings", "rooms", "facility_ids", "characteristics", "contacts",
  # "availability" (phase 6, failure-isolated). `key` stays a plain string
  # column (no `enum :key` macro) so the pipeline isn't hard-blocked by
  # ArgumentError if a future phase key is added — KEYS backs an inclusion
  # validation instead, which just marks the record invalid.
  KEYS = %w[campuses buildings rooms facility_ids characteristics contacts availability].freeze

  belongs_to :sync_run

  enum :status, { pending: "pending", running: "running", succeeded: "succeeded", failed: "failed", skipped: "skipped" }

  validates :key, presence: true, inclusion: { in: KEYS }, uniqueness: { scope: :sync_run_id }

  def duration_seconds
    return nil if started_at.blank? || finished_at.blank?

    finished_at - started_at
  end
end
