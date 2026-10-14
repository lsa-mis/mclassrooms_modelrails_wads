class SyncRun < ApplicationRecord
  include Tenanted
  include Broadcastable

  HISTORY_SIZE = 14

  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }

  has_many :sync_phases, dependent: :destroy

  scope :newest_first, -> { order(Arel.sql("COALESCE(started_at, created_at) DESC")) }

  def self.history_for(workspace) = where(workspace:).newest_first.limit(HISTORY_SIZE)

  def self.dry_run_by_default? = ENV["API_UPDATE_DELETE_DRY_RUN"].present?

  def self.typical_duration_for(workspace)
    where(workspace:).succeeded.where(dry_run: false).newest_first.first&.duration_seconds
  end

  def self.inventory_for(workspace)
    rooms = Room.where(workspace:)
    { buildings: Building.where(workspace:).listed.count, rooms: rooms.listed.count,
      classrooms: rooms.classroom.count, listed_classrooms: rooms.classroom.listed.count }
  end

  def self.fail_abandoned(workspace)
    now = Time.current
    abandoned = where(workspace:).running
    SyncPhase.where(sync_run: abandoned).running.update_all(status: "failed", finished_at: now, updated_at: now)
    abandoned.update_all(status: "failed", finished_at: now, updated_at: now)
  end

  def self.most_recent_for(workspace) = where(workspace:).newest_first.first

  def retryable? = failed? && self == SyncRun.most_recent_for(workspace)

  def duration_seconds
    return nil if started_at.blank? || finished_at.blank?

    finished_at - started_at
  end

  def phases_in_order = sync_phases.sort_by { |phase| SyncPhase::KEYS.index(phase.key) || SyncPhase::KEYS.size }

  def steps_total = Sync::RunPipeline::CORE_PHASES.size

  def steps_done = sync_phases.count { |phase| core_key?(phase.key) && (phase.succeeded? || phase.failed? || phase.skipped?) }

  def current_phase = sync_phases.find(&:running?)

  def progress_percent
    phase = current_phase
    within = phase&.items_total.to_i.positive? ? phase.items_done.to_f / phase.items_total : 0
    ((steps_done + within) * 100 / steps_total).floor
  end

  def changes_made = phases_in_order.flat_map { |phase| phase.changes_made.map { |counter, count| [ "#{phase.key}_#{counter}", count ] } }

  def change_count = changes_made.sum(&:last)

  private

  def core_key?(key) = Sync::RunPipeline::CORE_PHASES.any? { it::KEY == key }

  def broadcast_target = [ workspace, :sync_runs ]
end
