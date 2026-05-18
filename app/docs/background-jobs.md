---
title: Background Jobs
description: Solid Queue topology, named queues, recurring jobs, and the graduation path from in-Puma supervisor to dedicated bin/jobs host.
keywords: solid queue jobs mailers default low recurring digest cron observability mission control queue routing
audience: [guide, technical]
---

# Background Jobs

This template uses **Solid Queue** as its background job backend — the Rails 8 default. Jobs persist to SQLite (the same database that holds your app data, separated by Active Record's multi-DB support).

> **Design rationale:** queue topology decisions on this page came out of an Ops panel review. See [docs/superpowers/specs/2026-05-18-devcontainer-dockerfile-cleanup-design.md](https://github.com/dschmura/modelrails_base/blob/main/docs/superpowers/specs/2026-05-18-devcontainer-dockerfile-cleanup-design.md).

## Where jobs run

By default — and **per the template's design** — Solid Queue runs **inside the web server's Puma process**. The `SOLID_QUEUE_IN_PUMA: true` setting in `config/deploy.yml` activates the `puma-plugin-solid_queue` plugin, which starts the Supervisor as part of Puma's boot.

This means:

- **One container** handles HTTP requests *and* background jobs
- **One image deploy** updates both
- **No accessory networking** for the job runner
- **No SQLite-can't-reach-the-other-host problem**

It's the right default for a SQLite + one-VPS template. When you outgrow it, see [Graduation to a dedicated jobs host](#graduation-to-a-dedicated-jobs-host) below.

## Named queues (for observability)

`config/queue.yml` declares three named queues instead of the `queues: "*"` wildcard:

```yaml
workers:
  - queues: [ default, mailers, low ]
    threads: 3
    processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
    polling_interval: 0.1
```

**Why named queues?** With a single worker process + 3 threads sharing the GVL, splitting queues *doesn't* relieve contention — that's a multi-process win, not a multi-queue win. What named queues *do* give you is **observability**: when a queue backs up, you can see which class of work is slow.

| Queue | Convention | Examples |
|---|---|---|
| `default` | Business logic, sweeps, model callbacks, anything you `perform_later` without specifying a queue | `WorkspaceInvitationExpiringSweepJob`, custom callback jobs |
| `mailers` | Action Mailer / mailer-class jobs (network-bound, slower) | `DigestMailerJob`, `UserMailer.deliver_later` |
| `low` | Best-effort cleanup, retention sweeps — work that can wait without operational impact | Future use; reserved for jobs you'd be OK losing in a deploy edge case |

### Routing a job to a specific queue

Set `queue_as` in the job class:

```ruby
class DigestMailerJob < ApplicationJob
  queue_as :mailers

  def perform(...)
    # ...
  end
end
```

Or route at perform time:

```ruby
SomeJob.set(queue: :low).perform_later(arg)
```

Mailer jobs from `Mailer.deliver_later` calls automatically use the `mailers` queue if the Action Mailer adapter is configured for it (the Rails default since 8.0).

## Recurring jobs

Recurring jobs are declared in `config/recurring.yml` and dispatched by Solid Queue's scheduler. The template ships five:

| Job | Cadence | Queue | What it does |
|---|---|---|---|
| `clear_solid_queue_finished_jobs` | Every hour at :12 | (command, no queue) | Cleans up completed/failed jobs from Solid Queue's own tables in batches with 0.3s sleep between |
| `workspace_invitation_expiring_sweep` | Every 6 hours | `default` | Notifies users whose invitations expire soon (per-day idempotency) |
| `workspace_capacity_sweep` | Every 12 hours | `default` | Alerts workspace owners approaching member limits |
| `digest_mailer` | Every 15 minutes | `mailers` | Polls the `digest_next_due_at` index to send pending digest emails per each user's cadence |
| `notification_cleanup` | Daily at 3am UTC | `default` | Batched deletion of old notifications (chunks of 100 with SQLite lock release between transactions) |

### Why `digest_mailer` is on the `mailers` queue

It's the only currently-shipping recurring job that is **mailer-class work** — network-bound, can be slow due to SMTP timeouts. Routing it to `mailers` gives you a clean operational signal: when the `mailers` queue backs up, you know it's SMTP, not your sweep jobs.

### Adding a recurring job

Append to `config/recurring.yml`:

```yaml
production:
  my_new_job:
    class: MyNewJob
    queue: default     # or mailers / low
    schedule: every 30 minutes
```

Schedule syntax supports `every N seconds/minutes/hours/days`, `at H:Mam every day`, and full cron expressions. See [Solid Queue docs](https://github.com/rails/solid_queue) for the full schedule grammar.

## Mission Control (the job dashboard)

In development you can mount Solid Queue's Mission Control dashboard:

```ruby
# config/routes.rb (if not already present)
mount MissionControl::Jobs::Engine, at: "/jobs" if Rails.env.development?
```

In production, mount it behind Pundit authorization so only admins can see it. The dashboard shows per-queue throughput, in-flight jobs, failures, and retries — invaluable for debugging "why is X queue backed up?"

## Configuration knobs

| Setting | Default | Where | When to change |
|---|---|---|---|
| `JOB_CONCURRENCY` | `1` | `config/deploy.yml` env.clear | Increase only after migrating off `SOLID_QUEUE_IN_PUMA: true` — additional processes can't all run inside Puma |
| `threads: 3` | 3 | `config/queue.yml` | Lower to `2` if you measure SQLite write-lock contention; higher buys little because the GVL serializes Ruby work anyway |
| `polling_interval: 0.1` | 100ms | `config/queue.yml` | Lower = more responsive job pickup, more CPU spent polling. The default is fine for nearly all workloads |
| `dispatchers.batch_size: 500` | 500 | `config/queue.yml` | Tune up if you have huge backlog dispatch storms; rarely needed |

## Deploy-time behavior

When `kamal deploy` rolls a new container:

1. Solid Queue's `puma-plugin-solid_queue` receives the shutdown signal alongside Puma
2. Its `on_worker_shutdown` hook begins draining in-flight jobs
3. Kamal waits `stop_wait_time` seconds (45 by default — see [Deployment](/docs/deployment#stop_wait_time-45-at-top-level))
4. Any job that hasn't completed by then gets SIGKILLed and re-runs on the next container (via Solid Queue's at-least-once delivery semantics)

**Jobs you write should be idempotent.** Solid Queue gives you at-least-once delivery; deploys can SIGKILL mid-execution if `stop_wait_time` is too tight. Use database constraints, idempotency keys, or `find_or_create_by!` patterns instead of assuming "this job runs exactly once."

## Graduation to a dedicated jobs host

When you outgrow the in-Puma supervisor — typically because:

- Sustained job throughput exceeds ~10 jobs/sec
- You've added a second `web` host (which can't all run separate Solid Queue supervisors against the same SQLite file anyway)
- Recurring jobs are noticeably affecting HTTP p99 latency

…follow the four-step graduation checklist on [Deployment](/docs/deployment#graduation-checklist). The summary:

1. Add a database accessory (Postgres or MySQL)
2. Set `DB_HOST` in `env.clear`
3. Flip `SOLID_QUEUE_IN_PUMA` to `false`
4. Uncomment `servers.job:` in `deploy.yml` and deploy a separate `bin/jobs` supervisor

The same image runs in both `web` and `job` roles — only the `cmd` differs. Mission Control sees both supervisors and aggregates their queue stats.

## Local development

`bin/dev` (the default development command) runs Puma in foreground mode. With `SOLID_QUEUE_IN_PUMA` semantics also active in production, your local dev setup is intentionally similar — recurring jobs will fire on schedule when `bin/dev` is running.

If you want to test job processing in isolation:

```bash
bin/jobs   # Runs only the Solid Queue Supervisor, no Puma
```

Useful when you're iterating on a job and don't need web requests in the mix.

## See also

- [Deployment](/docs/deployment) — Kamal topology + the graduation path
- [Notifications](/docs/notifications) — User-facing side of recurring `digest_mailer` and friends
- [Notifications (technical)](/docs/notifications-technical) — `Noticed` integration with Solid Queue
- `config/queue.yml` — Worker configuration with inline comments
- `config/recurring.yml` — Schedule declarations
- [Solid Queue GitHub](https://github.com/rails/solid_queue) — Upstream docs and schedule syntax reference
