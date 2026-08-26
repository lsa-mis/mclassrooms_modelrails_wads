require "rails_helper"

# `ActivityLog.record_security_event!` enforces the security tier's invariant:
# it raises unless the action is in SECURITY_ACTIONS, and it owns the row shape
# in one place. That guard only protects callers who use it.
#
# This spec closes the bypass. Without it, a writer calling
# `ActivityLog.create!(action: "user.password_changed", visibility: "personal")`
# directly — or writing a near-miss literal like "user.passkey_add" — produces a
# row the retention sweep deletes at 12 months instead of the security floor,
# renders plausibly in the activity card via its humanizing `default:` fallback,
# and leaves the whole suite green. Audit evidence lost silently. That path was
# reachable the day the guard shipped (#824); no fourth writer was needed.
#
# Not a taste rule: an entry in either allow-list below is a reviewed decision
# about the write GUARANTEE a call site gets, which is the distinction
# app/models/concerns/trackable.rb's header exists to protect.
RSpec.describe "Code smell: security events route through record_security_event!" do
  # Locals, not constants: a constant here lands on Object, where another spec
  # file's same-named constant clobbers it whenever CI shards both into one
  # worker (the ALLOWED collision that broke CI on 2026-08-14).
  #
  # `record_security_event!` itself writes via a bare `create!` (implicit
  # receiver), so it does not match this pattern and needs no exemption.
  direct_writes = /\bActivityLog\.(create!?|insert(_all)?|upsert(_all)?)\b/

  # path => why this call site legitimately writes ActivityLog directly.
  # All three are BEST-EFFORT, workspace-domain writers — the other tier.
  # A security-tier write does not belong here; it belongs in the writer.
  allowed_direct_writes = {
    "app/models/concerns/trackable.rb" =>
      "the best-effort, workspace-domain write shape itself — the concern this " \
      "whole tier distinction is documented on",
    "app/models/membership.rb" =>
      "record_ownership_demotion, reached from a callback-skipping CAS " \
      "update_all, so the concern's callbacks cannot fire for it",
    "app/controllers/application_controller.rb" =>
      "log_blocked_role_grant, which records a REFUSAL — there is no persisted " \
      "record to track, so Trackable has nothing to hang off"
  }.freeze

  # Files allowed to mention a security-action literal without routing it
  # through the writer. Only the file that defines the set qualifies.
  literal_definers = [ "app/models/activity_log.rb" ].freeze

  def ruby_sources
    Dir[Rails.root.join("{app,lib}/**/*.rb")]
  end

  it "no app or lib code writes ActivityLog rows directly outside the reviewed best-effort writers" do
    offenders = ruby_sources.flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      next [] if allowed_direct_writes.key?(relative)

      File.readlines(file).each_with_index.filter_map do |line, i|
        "#{relative}:#{i + 1}: #{line.strip}" if line.match?(direct_writes)
      end
    end

    expect(offenders).to be_empty,
      "Security-tier rows go through ActivityLog.record_security_event!, which " \
      "raises on an action outside SECURITY_ACTIONS and owns the row shape. A " \
      "direct write bypasses both. Direct ActivityLog writes found:\n  " \
      "#{offenders.join("\n  ")}\nA legitimate best-effort writer belongs in " \
      "allowed_direct_writes in this spec, with its reason."
  end

  it "every file naming a security action routes it through the writer" do
    action_literal = Regexp.union(ActivityLog::SECURITY_ACTIONS)

    offenders = ruby_sources.filter_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      next if literal_definers.include?(relative)

      source = File.read(file)
      next unless source.match?(action_literal)
      next if source.include?("record_security_event!")

      relative
    end

    expect(offenders).to be_empty,
      "These files name a SECURITY_ACTIONS action but never call " \
      "record_security_event!, so nothing guarantees the action string is a " \
      "real member or that the row carries the security shape:\n  " \
      "#{offenders.join("\n  ")}"
  end
end
