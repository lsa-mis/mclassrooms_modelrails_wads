class SyncRun < ApplicationRecord
  include Tenanted

  HISTORY_SIZE = 14
  # A run still "running" past this was cut off (a deploy, a crash), so it neither blocks nor stays unretryable.
  STALL_AFTER = 6.hours

  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }

  has_many :sync_phases, dependent: :destroy

  # A run created but not yet started has no started_at, so ordering falls back to created_at.
  scope :newest_first, -> { order(Arel.sql("COALESCE(started_at, created_at) DESC")) }
  scope :in_progress, -> { running.where("COALESCE(started_at, created_at) > ?", STALL_AFTER.ago) }

  def self.latest = newest_first.first

  def self.history_for(workspace) = where(workspace:).newest_first.limit(HISTORY_SIZE)

  def self.in_progress_for?(workspace) = where(workspace:).in_progress.exists?

  def self.dry_run_by_default? = ENV["API_UPDATE_DELETE_DRY_RUN"].present?

  def self.inventory_for(workspace)
    rooms = Room.where(workspace:)
    { buildings: Building.where(workspace:).listed.count, rooms: rooms.listed.count,
      classrooms: rooms.classroom.count, listed_classrooms: rooms.classroom.listed.count }
  end

  # Operator verbs: each writes one admin-visible audit row, then enqueues the pipeline after commit.
  def self.request!(workspace:, by:)
    return :already_running if in_progress_for?(workspace)

    run = new(workspace:, dry_run: dry_run_by_default?, status: :running)
    run.enqueue_audited!("sync_run.requested", by:)
    :requested
  end

  def resume!(by:)
    return :not_resumable unless resumable?
    return :already_running if SyncRun.in_progress_for?(workspace)

    assign_attributes(status: :running, finished_at: nil)
    enqueue_audited!("sync_run.resumed", by:)
    :resumed
  end

  def queued? = running? && started_at.nil? && !stalled?
  def stalled? = running? && (started_at || created_at || Time.current) <= STALL_AFTER.ago
  def resumable? = failed? || stalled?

  def display_status
    return :stalled if stalled?
    return :queued if queued?

    status.to_sym
  end

  def duration_seconds
    return nil if started_at.blank? || finished_at.blank?

    finished_at - started_at
  end

  def phases_in_order = sync_phases.sort_by { |phase| SyncPhase::KEYS.index(phase.key) || SyncPhase::KEYS.size }

  # Public so SyncRun.request! can call it on the run it builds.
  def enqueue_audited!(action, by:)
    result = Curation::Apply.call(record: self, actor: by, action:, workspace:)
    raise ActiveRecord::RecordNotSaved.new(result.errors.to_sentence, self) unless result.success?

    SyncRunJob.perform_later(self)
  end
end
