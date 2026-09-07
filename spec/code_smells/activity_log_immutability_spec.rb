require "rails_helper"

# ActivityLog#readonly? blocks instance-level rewrites, but relation-level
# writes (update_all/delete_all/destroy_all/upsert) and raw SQL skip that
# check entirely. This spec closes the bypass: audit history stays
# append-only in app code until a retention policy (#438) designs its
# explicit carve-out — which should be added to ALLOWED below, not disabled
# inline.
RSpec.describe "Code smell: activity log immutability" do
  # Locals, not constants: a constant here lands on Object, where another
  # spec file's same-named constant clobbers it whenever CI shards both into
  # one worker (the ALLOWED collision that broke CI on 2026-08-14).
  # `(?:\.|&:)` — the batched idiom `in_batches(of: 100, &:delete_all)`
  # passes delete_all as a SYMBOL, which the original dotted-call pattern
  # missed entirely (found when the #438 retention job failed to trip this
  # guard as designed).
  # `dependent:` is the third spelling, and it slipped through until #921:
  # `has_many :activity_logs, dependent: :delete_all` deletes rows relation-
  # level exactly like the dotted call, but the separator is `: ` rather than
  # `.` or `&:`. A guard that exists to make relation-level deletion a REVIEWED
  # decision has to see the association form too.
  bypass_writes = /\b(?:ActivityLog|activity_logs)\b[^\n]*(?:(?:\.|&:)(?:update_all|delete_all|destroy_all|update_columns|upsert(?:_all)?)|dependent:\s*:(?:delete_all|destroy_all))\b/

  # path => reason. Empty until the #438 retention job exists.
  # The documented door through the immutability guarantee — an entry here is
  # a reviewed decision, never an inline disable. This is how the carve-out
  # is meant to be exercised (#438): reason attached, in the guard's own file.
  allowed_bypasses = {
    "app/jobs/activity_log_retention_sweep_job.rb" =>
      "the panel-decided retention sweep (#438), now two-grade: 12-month " \
      "window for best-effort workspace rows, SECURITY_RETENTION_FLOOR for " \
      "strict account-security rows (notifications lifecycle arc) — see the " \
      "job's header",
    "app/models/workspace.rb" =>
      "#921: a workspace's own audit trail dies with it. `:delete_all` rather " \
      "than `:destroy` because ActivityLog#readonly? is persisted?, so " \
      "instance-level destroy raises by design — relation-level is the only " \
      "door. Cannot reach the security tier: record_security_event! hardcodes " \
      "workspace_id: nil, so no SECURITY_ACTIONS row is in the association's scope"
  }.freeze

  it "no app or lib code rewrites or deletes activity log rows" do
    offenders = Dir[Rails.root.join("{app,lib}/**/*.rb")].flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      next [] if allowed_bypasses.key?(relative)

      File.readlines(file).each_with_index.filter_map do |line, i|
        "#{relative}:#{i + 1}: #{line.strip}" if line.match?(bypass_writes)
      end
    end

    expect(offenders).to be_empty,
      "The audit trail is append-only (best-effort to write, impossible to " \
      "rewrite — see /docs/developer/architecture). Relation-level writes found:\n  " \
      "#{offenders.join("\n  ")}\nA legitimate retention job belongs in " \
      "allowed_bypasses in this spec with its reason."
  end
end
