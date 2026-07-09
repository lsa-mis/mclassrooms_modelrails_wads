# Nightly trigger for the U-M Facilities sync pipeline (Task 12 of
# planning/plans/phase-2-ingestion.md; roadmap Lib section; spec D7).
# Scheduled via Solid Queue recurring tasks (config/recurring.yml:
# nightly_sync, 2:30am America/Detroit) rather than host cron, per spec D7's
# "Scheduling via Solid Queue recurring tasks... not host cron."
#
# Current.workspace: MiClassrooms is single-tenant (Task 4) — the sync has
# exactly one workspace to target, not a per-request tenant, so per the
# template's job rule (CLAUDE.md deviation #1: "jobs must establish
# workspace context explicitly") this resolves and sets Current.workspace
# itself before calling the pipeline, the same TenancyConfig.
# shared_workspace_slug lookup DirectoryScoped uses for web requests
# (app/controllers/concerns/directory_scoped.rb) — just without that
# concern's redirect-on-missing fallback, since a job has no request to
# redirect. Sync::UpdateCampuses's spec header notes this is deliberately
# the pipeline job's responsibility, not BasePhase's or the phases' own.
#
# Never raises on a sync failure: Sync::RunPipeline.call already contains
# every phase failure in a Result/SyncPhase row and never propagates out of
# `.call` (BasePhase's invariant, Task 6, extended by the pipeline's own
# bookkeeping rescue, Task 12) — a failed nightly sync shows up as a
# `failed` SyncRun for an operator to read, not as a Solid Queue job
# failure/retry storm. A missing/misconfigured shared workspace, by
# contrast, IS a genuine setup bug worth a loud job failure (visible in the
# mission_control-jobs dashboard) rather than being silently swallowed here.
class SyncNightlyJob < ApplicationJob
  queue_as :default

  def perform
    Current.workspace = Workspace.kept.find_by!(slug: TenancyConfig.shared_workspace_slug)
    Sync::RunPipeline.call
  end
end
