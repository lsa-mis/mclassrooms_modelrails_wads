# frozen_string_literal: true

# The single reviewed list of files permitted to write ActivityLog rows
# directly, outside Trackable and record_security_event!.
# spec/code_smells/security_events_route_through_writer_spec.rb proves no
# OTHER file writes directly; dynamic_i18n_keys_have_values_spec.rb derives
# the literal actions these four files may write FROM this same list, rather
# than regex-scanning app/ for the `ActivityLog.create!` shape. A new bypass
# writer must be added here first, so it cannot ship invisible to either
# guard.
#
# A module constant, not a `describe`-block local: a bare constant assigned
# inside a top-level `describe` block lands on Object, not the block's own
# namespace, and collides across spec files CI shards into one worker (the
# ALLOWED collision that broke CI).
module SecurityEventWriters
  # path => why this call site legitimately writes ActivityLog directly. All
  # four are BEST-EFFORT, workspace-domain writers — a security-tier write
  # does not belong here; it goes through record_security_event! instead.
  ALLOWED = {
    "app/models/concerns/trackable.rb" =>
      "the best-effort, workspace-domain write shape itself — the concern this " \
      "whole tier distinction is documented on",
    "app/models/membership/ownership.rb" =>
      "record_ownership_demotion, reached from a callback-skipping CAS " \
      "update_all, so the concern's callbacks cannot fire for it",
    "app/controllers/application_controller.rb" =>
      "log_blocked_role_grant, which records a REFUSAL — there is no persisted " \
      "record to track, so Trackable has nothing to hang off",
    "app/models/invitation/suppression.rb" =>
      "record_suppressed_delivery — best-effort, admin-visibility, fired from " \
      "mailer callbacks where Trackable's hooks must not run (a block oracle " \
      "otherwise)",
    "app/lib/curation/apply.rb" =>
      "fork: the admin-curation writer — workspace-tier before/after rows " \
      "written INSIDE the curated change's transaction (deliberately not " \
      "best-effort; the audit row and the change commit together). Curation " \
      "actions are never SECURITY_ACTIONS"
  }.freeze
end
