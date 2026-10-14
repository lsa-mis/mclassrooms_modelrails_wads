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
- A request made while a sync is queued or running is **dropped**. Solid Queue doesn't store it, so the job comes back without a `provider_job_id`; that is how `SyncRunJob.request` knows, and the operator is told nothing new started.
- The lock is taken when the job is **queued** and lasts `DURATION` from then. It is released when the job finishes, or when Solid Queue cleans up a worker process that died.
- **`DURATION` (12 hours) must be longer than any real sync, including time spent waiting in the queue.** If a sync outlived it, a second one could start beside it. It is set far above the expected sync time on purpose: a crashed worker releases its lock when Solid Queue cleans the process up, so a long duration only matters if that clean-up never happens.

Two consequences follow:

- **A crashed worker leaves its run marked "running".** The next sync to start is, by construction, the only one for its workspace, so it marks any run still "running", and that run's running steps, as failed before it begins. To recover from a crash, use Run now. The abandoned run then shows as failed and can be retried if it's the most recent.
- **The test suite can't run Solid Queue's locking.** The test adapter ignores `limits_concurrency`, and the test environment has no queue database. `spec/jobs/sync_run_job_spec.rb` checks the declaration; the guarantee itself is Solid Queue's.

## The pipeline

`Sync::RunPipeline.call(run:)` runs the phases for one run:

- **Core phases run in a fixed order and stop at the first failure:** campuses, buildings, rooms, facility IDs, characteristics, contacts. The steps after a failure are marked `skipped`, not left `pending`, so "never ran" and "didn't get to it" read differently.
- **Optional phases** (`OPTIONAL_PHASES`) run after the core ones whatever happened, and their failure never changes the run's status.
- **The gateway's 400-calls-a-minute budget is held by `UmApi::RateLimiter`,** call by call, with a back-off when the gateway answers 429. Phases run back to back; the 61-second pause the legacy app slept between phases was dropped once the limiter enforced the same budget.
- **One API client per run** is shared by every phase, so each phase's `api_calls` and `rate_limit_sleeps` counters come from one running total. It keeps one connection open for the run, and `get_json(remember: true)` keeps a successful response for the rest of the run: the characteristics phase reuses the `/Characteristics` responses the facility-IDs phase already fetched. The client raises `UmApi::RateLimited` on a 429; retrying is the caller's job, through `rate_limiter.backoff_429`.
- **It never raises once the run exists.** A phase returns a `Result` and records its own failure. The pipeline's own bookkeeping errors mark the run failed. Only failing to *create* the run raises, because there's nowhere to record that.

## What the phases may change

- **Only the rooms phase creates rooms.** The facility-IDs phase matches existing rooms by `rmrecnbr` and writes `facility_code` and `campus`; a room number it can't match is skipped with a warning, once per run however many facilities list it.
- **The classroom list is fetched once and grouped by `BuildingID` in Ruby.** Whether the gateway honours a `BuildingID` filter on that endpoint is unverified, and a filter it silently ignored would hand every building the whole list.
- **The facility-to-room crosswalk comes from `/Characteristics`.** The classroom list carries no room number, so the facility-IDs phase reads each facility's `/Characteristics` rows for their `RmRecNbr`; one facility can cover several rooms. A 429 there retries only that facility. A facility whose response is empty contributes no rooms, with no warning; one whose fetch fails outright (not found, server error) is skipped with a warning. Neither is guessed at, and both keep their rooms: the sweep below leaves alone any room whose facility code belongs to a facility that is still on the classroom list but couldn't be read this run.
- **A classroom that leaves the classroom list loses its facility code; it isn't deactivated.** Offices and labs are never on that list, so deactivating on absence would retire them nightly. Only rooms holding a facility code are swept, so a room that never had one is never touched. Clearing the code drops the room from Find-a-Room, and the next sync that finds it restores it. `in_feed` belongs to the rooms phase alone.
- **A stale sweep is skipped, with a warning, only when its whole feed comes back empty,** so a gateway glitch can't retire everything at once. In the facility-IDs phase, a facility that failed or came back empty is also kept out of the sweep, so one bad response can't drop its rooms from Find-a-Room.
- **The capacity filter's maximum is recomputed last** in the facility-IDs phase, so it runs only when the phase got that far, with seat counts the rooms phase already wrote.

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
