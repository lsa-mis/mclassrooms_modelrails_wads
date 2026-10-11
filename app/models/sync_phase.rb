class SyncPhase < ApplicationRecord
  include Tenanted
  include Broadcastable

  # Reference list of phase keys the pipeline (phase 2) writes: "campuses",
  # "buildings", "rooms", "facility_ids", "characteristics", "contacts",
  # "availability" (phase 6, failure-isolated). `key` stays a plain string
  # column (no `enum :key` macro) so the pipeline isn't hard-blocked by
  # ArgumentError if a future phase key is added — KEYS backs an inclusion
  # validation instead, which just marks the record invalid.
  KEYS = %w[campuses buildings rooms facility_ids characteristics contacts availability].freeze
  CHANGE_COUNTERS = %w[created updated added removed cleared deactivated deleted].freeze

  belongs_to :sync_run

  enum :status, { pending: "pending", running: "running", succeeded: "succeeded", failed: "failed", skipped: "skipped" }

  validates :key, presence: true, inclusion: { in: KEYS }, uniqueness: { scope: :sync_run_id }

  def duration_seconds
    return nil if started_at.blank? || finished_at.blank?

    finished_at - started_at
  end

  def changes_made = counters.slice(*CHANGE_COUNTERS).select { |_counter, count| count.positive? }

  private

  def broadcast_target = [ workspace, :sync_runs ]
end
