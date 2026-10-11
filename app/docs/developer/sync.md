---
title: Facilities sync
description: How the nightly U-M Facilities sync runs, how it resumes after a failure, how only one runs at a time, and the pages that show and control it
keywords: sync sync_run pipeline nightly facilities um_api resume retry run now limits_concurrency solid queue operations sync_runs
---

# Facilities sync

MClassrooms takes its campuses, buildings, rooms, characteristics and contacts from the U-M Facilities APIs. A sync is one pass over those APIs, recorded as a `SyncRun` with one `SyncPhase` per step.

## Where a sync starts

Every sync is a `SyncRunJob`. Three things enqueue it:

| Trigger | Where | Audited |
| --- | --- | --- |
| Nightly | `config/recurring.yml` runs `SyncNightlyJob` at 2:30am Detroit time, which enqueues `SyncRunJob` | No, nobody asked for it |
| Run now | An operator on `/operations/sync_runs` | Yes, `sync_run.requested` |
| Retry | An operator on the most recent failed run | Yes, `sync_run.resumed` |

The job creates the run when it actually starts. An enqueue that fails leaves nothing behind.

## One sync at a time

`SyncRunJob` declares Solid Queue's concurrency control:

```ruby
limits_concurrency to: 1, key: ->(workspace, **) { workspace }, duration: DURATION, on_conflict: :discard
```

- At most one sync runs per workspace. All three triggers share the same key, so they all count.
- A request made while a sync is queued or running is **dropped**. Solid Queue doesn't store it, and the operator is told nothing new started.
- The lock is taken when the job is **queued** and lasts `DURATION` from then. It is released when the job finishes, or when Solid Queue cleans up a worker process that died.
- **`DURATION` (12 hours) must be longer than any real sync, including time spent waiting in the queue.** If a sync outlived it, a second one could start beside it. It is set far above the expected sync time on purpose: a crashed worker releases its lock when Solid Queue cleans the process up, so a long duration only matters if that clean-up never happens.

Two consequences follow:

- **A crashed worker leaves its run marked "running".** The next sync to start is, by construction, the only one for its workspace, so it marks any run still "running", and that run's running steps, as failed before it begins. To recover from a crash, use Run now. The abandoned run then shows as failed and can be retried if it's the most recent.
- **The test suite can't run Solid Queue's locking.** The test adapter ignores `limits_concurrency`, and the test environment has no queue database. `spec/jobs/sync_run_job_spec.rb` checks the declaration; the guarantee itself is Solid Queue's.

## The pipeline

`Sync::RunPipeline.call(run:)` runs the phases for one run:

- **Core phases run in a fixed order and stop at the first failure:** campuses, buildings, rooms, facility IDs, characteristics, contacts. The steps after a failure are marked `skipped`, not left `pending`, so "never ran" and "didn't get to it" read differently.
- **Optional phases** (`OPTIONAL_PHASES`) run after the core ones whatever happened, and their failure never changes the run's status.
- **There's a 61-second pause between phases** that actually run, to keep within the gateway's 400-calls-a-minute budget. Specs inject `sleeper:` so they never really sleep.
- **One API client per run** is shared by every phase, so each phase's `api_calls` and `rate_limit_sleeps` counters come from one running total.
- **It never raises once the run exists.** A phase returns a `Result` and records its own failure. The pipeline's own bookkeeping errors mark the run failed. Only failing to *create* the run raises, because there's nowhere to record that.

## Resuming

Passing a failed run resumes it. Every phase that already succeeded is skipped, and the rest run again. A run that stopped at rooms re-runs rooms through contacts. The retry gets its own start time, so its duration and its place in the history belong to the retry.

Retry is offered only on the **most recent** run, and only when it failed. Re-running an old run's leftover steps against today's data would change nothing useful.

## The pages

| Page | Who | Shows |
| --- | --- | --- |
| `/admin/sync_runs` | Directory admins and editors | The latest run, current inventory counts, the recent runs, and each run's steps with every counter, errors and warnings |
| `/operations/sync_runs` | Operators | The same, plus **Run now** and **Retry** |

Both pages render the shared partials in `app/views/sync_runs/`. Editors reach the admin page by URL; there's no editor menu yet.

---

**Related:** [Operations](/docs/developer/operations) · [Background jobs](/docs/developer/background-jobs) · [Production deployment](/docs/developer/deployment-miclassrooms)
