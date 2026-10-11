class SyncRun < ApplicationRecord
  include Tenanted

  HISTORY_SIZE = 14

  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }

  has_many :sync_phases, dependent: :destroy

  scope :newest_first, -> { order(Arel.sql("COALESCE(started_at, created_at) DESC")) }

  def self.history_for(workspace) = where(workspace:).newest_first.limit(HISTORY_SIZE)

  def self.dry_run_by_default? = ENV["API_UPDATE_DELETE_DRY_RUN"].present?

  def self.inventory_for(workspace)
    rooms = Room.where(workspace:)
    { buildings: Building.where(workspace:).listed.count, rooms: rooms.listed.count,
      classrooms: rooms.classroom.count, listed_classrooms: rooms.classroom.listed.count }
  end

  # Called only by SyncRunJob, which runs one sync per workspace at a time: any run still marked running
  # was left by a worker that died, so it is failed and can be retried.
  def self.fail_abandoned(workspace)
    where(workspace:).running.update_all(status: "failed", finished_at: Time.current, updated_at: Time.current)
  end

  def duration_seconds
    return nil if started_at.blank? || finished_at.blank?

    finished_at - started_at
  end

  def phases_in_order = sync_phases.sort_by { |phase| SyncPhase::KEYS.index(phase.key) || SyncPhase::KEYS.size }
end
