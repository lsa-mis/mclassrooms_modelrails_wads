# frozen_string_literal: true

# The dispatch watermark for #927.
#
# `Noticed::Deliverable#deliver` commits the event and its notification rows in
# a transaction and then enqueues `Noticed::EventJob` outside it. Solid Queue
# writes to a separate SQLite database in production, so that enqueue can never
# be atomic with the primary write — and moving it inside the write transaction
# is ruled out by the lock-ordering decision recorded in `Workspace` and
# `app/docs/developer/architecture.md`. An enqueue that fails (Solid Queue's
# database busy past its timeout, a full disk) or a process death in the gap
# therefore leaves committed rows — and a consumed idempotency key — with no
# email and no broadcast behind them.
#
# So the job stamps its own arrival. Stamped at the START of `perform`, not the
# end: an event whose job was CLAIMED is already stamped, so
# `NotificationDispatchReconcileJob` covers only the never-enqueued gap and can
# never re-run an event whose delivery legs already fanned out.
#
# What that deliberately does NOT cover: a claimed job that then raises.
# `Noticed::EventJob` declares no `retry_on` (only
# `discard_on ActiveJob::DeserializationError`), so it lands in
# `solid_queue_failed_executions` and waits for a manual retry — there is no
# automatic recovery and no dashboard here. Closing that is #1065.
#
# `before_perform` rather than an override: the gem hardcodes `EventJob` at
# `Deliverable#deliver`, so no subclass can be substituted. `update_column`
# skips callbacks and validations deliberately — this is bookkeeping on a gem
# model, not a domain write, and it must not fire `after_create_commit`
# broadcasts or touch `updated_at`.
Rails.application.config.to_prepare do
  # `to_prepare` runs on every reload in development, but `Noticed::EventJob`
  # lives in the gem's engine and is not reloaded with the app — registering
  # unconditionally would stack a duplicate callback per reload. The guard is
  # correct either way: a class that IS reloaded arrives without the ivar.
  unless Noticed::EventJob.instance_variable_get(:@dispatch_watermark_registered)
    Noticed::EventJob.instance_variable_set(:@dispatch_watermark_registered, true)

    Noticed::EventJob.before_perform do |job|
      job.arguments.first&.update_column(:dispatched_at, Time.current)
    end
  end
end
