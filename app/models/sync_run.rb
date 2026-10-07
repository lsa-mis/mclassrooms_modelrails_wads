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

  # The one place a new run starts: a partial unique index allows one running run per workspace, and a
  # stalled run is failed first so it never blocks. The caller saves the yielded run; nil means one is running.
  def self.reserve(workspace:)
    run = new(workspace:, dry_run: dry_run_by_default?, status: :running)
    transaction do
      fail_stalled(workspace)
      yield run
    end
    run
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def self.fail_stalled(workspace)
    where(workspace:).running.where("COALESCE(started_at, created_at) <= ?", STALL_AFTER.ago)
      .update_all(status: "failed", finished_at: Time.current, updated_at: Time.current)
  end

  # Operator verbs: the audit row commits with the reservation; the pipeline is enqueued after commit.
  def self.request!(workspace:, by:)
    run = reserve(workspace:) { |reserved| reserved.audit!("sync_run.requested", by:) }
    return :already_running unless run

    SyncRunJob.perform_later(run)
    :requested
  end

  def resume!(by:)
    outcome = SyncRun.transaction do
      SyncRun.fail_stalled(workspace)
      next :not_resumable unless claim_retry

      reload.audit!("sync_run.resumed", by:)
      :resumed
    end
    SyncRunJob.perform_later(self) if outcome == :resumed
    outcome
  rescue ActiveRecord::RecordNotUnique
    reload
    :already_running
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

  # Public so SyncRun.request! can audit the run it reserves.
  def audit!(action, by:)
    result = Curation::Apply.call(record: self, actor: by, action:, workspace:)
    raise ActiveRecord::RecordNotSaved.new(result.errors.to_sentence, self) unless result.success?

    self
  end

  private

  # A conditional UPDATE, so of two simultaneous retries only one wins; the new attempt gets a fresh start time.
  def claim_retry
    now = Time.current
    SyncRun.where(id:, status: "failed").update_all(status: "running", finished_at: nil, started_at: now, updated_at: now) == 1
  end
end
