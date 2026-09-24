require "rails_helper"

# `ActivityLog.record_security_event!` enforces the security tier's invariant:
# it raises unless the action is in SECURITY_ACTIONS, and it owns the row shape
# in one place. That guard only protects callers who use it.
#
# This spec closes the bypass. Without it, a writer calling
# `ActivityLog.create!(action: "user.password_changed", visibility: "personal")`
# directly — or writing a near-miss literal like "user.passkey_add" — produces a
# row the retention sweep deletes at 12 months instead of the security floor,
# and leaves the whole suite green. Audit evidence lost silently. That path was
# reachable the day the guard shipped (#824); no fourth writer was needed.
#
# Not a taste rule: an entry in either allow-list below is a reviewed decision
# about the write GUARANTEE a call site gets, which is the distinction
# app/models/concerns/trackable.rb's header exists to protect.
RSpec.describe "Code smell: security events route through record_security_event!" do
  # `record_security_event!` itself writes via a bare `create!` (implicit
  # receiver), so it does not match this pattern and needs no exemption.
  # Covers both the class-level shape (ActivityLog.create!/.new/.insert_all/
  # .upsert_all) and the association shape (workspace.activity_logs.create!,
  # live via Workspace has_many :activity_logs) — a narrower regex covering
  # only the class-level shape let both escape (a probe file in each shape
  # stayed off the offender list).
  direct_writes = /\bActivityLog\.(create!?|new|insert(_all)?|upsert(_all)?)\b|\bactivity_logs\.(create!?|insert(_all)?|upsert(_all)?)\b/

  # SecurityEventWriters::ALLOWED (spec/support/security_event_writers.rb) is
  # the single reviewed list, shared with dynamic_i18n_keys_have_values_spec.rb
  # — see that file's header for why it is a module constant rather than a
  # `describe`-block local.
  allowed_direct_writes = SecurityEventWriters::ALLOWED

  # Files allowed to mention a security-action literal without routing it
  # through the writer. Only the file that defines the set qualifies —
  # operatorship.rb now calls record_security_event! like every other writer,
  # so it satisfies the third example below on its own.
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

  # POSITIVE CONTROL — the example below asserts an empty list, which a pattern
  # that matches nothing also produces. These are the two shapes that must stay
  # distinguishable: an action written as a string, and a predicate that merely
  # contains one.
  it "matches an action string and not a predicate that contains one" do
    pattern = Regexp.union(
      ActivityLog::SECURITY_ACTIONS.map { |action| /["']#{Regexp.escape(action)}["']/ }
    )

    expect('ActivityLog.create!(action: "user.suspended")').to match(pattern)
    expect("raise User::SuspendedError if auth.user.suspended?").not_to match(pattern)
  end

  it "carries no stale exemptions" do
    live_files = ruby_sources
      .select { |file| File.read(file).match?(direct_writes) }
      .map { |file| Pathname(file).relative_path_from(Rails.root).to_s }
    stale = allowed_direct_writes.keys - live_files

    expect(stale).to be_empty,
      "These exemptions name a file that no longer writes ActivityLog directly — " \
      "the allow-list is describing code that moved or went away, and because the " \
      "scan above skips an exempted file whole, a stale key would silently cover a " \
      "future direct write in it:\n  #{stale.join("\n  ")}"
  end

  # Per-file by design. Since the model decomposition, app/models/user/password.rb
  # must satisfy this on its own (it names the literal and calls the writer); a
  # split that separates the two breaks this example, and should.
  it "every file naming a security action routes it through the writer" do
    # QUOTED, because the bare literal is a substring of ordinary Ruby: the
    # action `user.suspended` sits inside `auth.user.suspended?`, an ordinary
    # predicate call that names no action at all. An unquoted match reported
    # that as a file writing security rows without the writer. The rule is
    # about action STRINGS, so the pattern says so rather than the call sites
    # bending around it.
    action_literal = Regexp.union(
      ActivityLog::SECURITY_ACTIONS.map { |action| /["']#{Regexp.escape(action)}["']/ }
    )

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
