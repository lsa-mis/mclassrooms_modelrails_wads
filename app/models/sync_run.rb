class SyncRun < ApplicationRecord
  include Tenanted

  HISTORY_SIZE = 14
  # A live sync beats at least every few minutes (each API call, each phase); quiet this long, its worker is gone.
  STALL_AFTER = 15.minutes
  LAST_SIGN_OF_LIFE = "COALESCE(heartbeat_at, started_at, updated_at)".freeze

  # Raised in a worker whose attempt a retry has taken over, so it stops instead of writing over the retry.
  Superseded = Class.new(StandardError)

  enum :status, { running: "running", succeeded: "succeeded", failed: "failed" }

  has_many :sync_phases, dependent: :destroy

  # A run that has not started yet has no started_at; its queue time is updated_at (bumped by a retry).
  scope :newest_first, -> {
    order(Arel.sql("CASE WHEN started_at IS NULL AND status = 'running' THEN updated_at " \
                   "ELSE COALESCE(started_at, created_at) END DESC"))
  }
  scope :in_progress, -> { running.where("#{LAST_SIGN_OF_LIFE} > ?", STALL_AFTER.ago) }

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
    where(workspace:).running.where("#{LAST_SIGN_OF_LIFE} <= ?", STALL_AFTER.ago)
      .update_all(status: "failed", finished_at: Time.current, updated_at: Time.current)
  end

  # Operator verbs: the audit row commits with the reservation; the job is queued after commit.
  def self.request!(workspace:, by:)
    run = reserve(workspace:) { |reserved| reserved.audit!("sync_run.requested", by:) }
    return :already_running unless run

    run.dispatch ? :requested : :not_queued
  end

  def resume!(by:)
    outcome = SyncRun.transaction do
      SyncRun.fail_stalled(workspace)
      next :not_resumable unless claim_retry

      reload.audit!("sync_run.resumed", by:)
      :resumed
    end
    return outcome unless outcome == :resumed

    dispatch ? :resumed : :not_queued
  rescue ActiveRecord::RecordNotUnique
    reload
    :already_running
  end

  # SyncRunJob's gate: only a job for the current attempt, and only the first of them, gets to run the row.
  def claim_execution(for_attempt)
    now = Time.current
    SyncRun.where(id:, attempt: for_attempt, status: "running", started_at: nil)
      .update_all(started_at: now, heartbeat_at: now, updated_at: now) == 1
  end

  # The worker's lease: renewed only while this attempt still owns the run, so a superseded worker stops here.
  def beat!
    return if fenced.update_all(heartbeat_at: Time.current, updated_at: Time.current) == 1

    raise Superseded, "sync run #{id} attempt #{attempt} was taken over by a retry"
  end

  # The worker's last write, fenced the same way; false means a retry owns the run and nothing was written.
  def finish!(outcome)
    now = Time.current
    return false unless fenced.update_all(status: outcome.to_s, finished_at: now, updated_at: now) == 1

    reload
    true
  end

  # The queue is a separate database, so a failed enqueue cannot roll the reservation back; release it instead.
  def dispatch
    return true if SyncRunJob.perform_later(self, attempt)

    release("enqueue returned false")
  rescue StandardError => e
    Rails.error.report(e, handled: true, context: { sync_run_id: id })
    release(e.class.name)
  end

  def queued? = running? && started_at.nil? && !stalled?
  def stalled? = running? && (heartbeat_at || started_at || updated_at || Time.current) <= STALL_AFTER.ago
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

  def fenced = SyncRun.where(id:, attempt:, status: "running")

  # A conditional UPDATE, so of two simultaneous retries only one wins. The retry is a new, queued attempt,
  # which retires any job still holding the old one.
  def claim_retry
    SyncRun.where(id:, status: "failed").update_all(
      [ "status = 'running', finished_at = NULL, started_at = NULL, attempt = attempt + 1, updated_at = ?", Time.current ]
    ) == 1
  end

  def release(reason)
    Rails.logger.error("[sync] could not queue sync run #{id} (#{reason}); released it")
    update_columns(status: "failed", finished_at: Time.current, updated_at: Time.current)
    false
  end
end
