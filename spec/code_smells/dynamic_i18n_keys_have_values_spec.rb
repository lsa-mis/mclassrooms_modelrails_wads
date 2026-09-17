require "rails_helper"

# Two labels are looked up by a dynamic key — `settings.sessions.activity.<action>`
# for every ActivityLog::SECURITY_ACTIONS member, and `authentication.providers.<key>`
# for every configured sign-in provider — and they used to carry inline defaults
# so a member without a label rendered humanized text. Neither i18n gate can see
# a dynamic key (the static one cannot read it, the runtime one only fires on a
# path a spec walks), so this spec is the gate: add the member, add its label, or
# this is red. See /docs/developer/i18n (No inline defaults).
RSpec.describe "Code smell: every dynamic i18n key has a value" do
  it "labels every security action on the account activity list" do
    missing = ActivityLog::SECURITY_ACTIONS.reject { |action| I18n.exists?("settings.sessions.activity.#{action}") }

    expect(missing).to be_empty,
      "Security actions without a settings.sessions.activity label:\n  #{missing.join("\n  ")}"
  end

  it "labels the os variant of every action whose writer records an os" do
    missing = ActivityLog::SECURITY_ACTIONS_WITH_OS.reject do |action|
      I18n.exists?("settings.sessions.activity.#{action}_with_os")
    end

    expect(missing).to be_empty,
      "OS-labeled actions without a _with_os label:\n  #{missing.join("\n  ")}"
  end

  it "labels every sign-in provider, the email one included" do
    # Registry keys are OmniAuth strategy names; the stored provider is the normalized one.
    providers = Rails.application.config.x.oauth_providers.keys.map { |key| OmniauthAdapters.normalize_provider(key.to_s) } + [ "email" ]
    missing = providers.reject { |provider| I18n.exists?("authentication.providers.#{provider}") }

    expect(missing).to be_empty,
      "Providers without an authentication.providers label:\n  #{missing.join("\n  ")}"
  end

  # Both activity feeds render `activity.actions.<display_action>`.
  # Trackable-derived actions are enumerable from the model layer; the rest
  # bypass Trackable with a literal `action:`. Two scans read the SAME two
  # reviewed sources security_events_route_through_writer_spec.rb pins —
  # SecurityEventWriters::ALLOWED for the `ActivityLog.create!` shape, and
  # every `record_security_event!` call under app/ for a non-personal
  # `visibility:` — using balanced_end (a nested `)` can't hide `action:`)
  # and without_comments (prose can't forge a phantom action).
  #
  # Neither scan can resolve every Ruby shape (no parens, a non-literal
  # value, a string-embedded paren). Anything unresolved to a plain string
  # literal fails loud, naming the file and line, rather than skipping
  # silently and shipping a missing label unnoticed.
  def action_arg_pattern
    /\baction:\s*(.+?)\s*(?:,|\z)/m
  end

  # Sibling to action_arg_pattern, same shape, for pulling a call's
  # visibility: argument instead of its action: one.
  def visibility_arg_pattern
    /\bvisibility:\s*(.+?)\s*(?:,|\z)/m
  end

  describe "the action: extraction regex" do
    it "is not fooled by a preceding kwarg ending in \"action:\"" do
      call_args = %(transaction: true, action: "workspace.updated")
      expect(call_args.match(action_arg_pattern)[1]).to eq('"workspace.updated"')
    end

    it "does not match a kwarg ending in \"action:\" when no real action: is present" do
      call_args = %(redaction: "a.b")
      expect(call_args.match(action_arg_pattern)).to be_nil
    end
  end

  describe "the visibility: extraction regex" do
    it "is not fooled by a preceding kwarg ending in \"visibility:\"" do
      call_args = %(default_visibility: "admin", action: "a.b", visibility: "personal")
      expect(call_args.match(visibility_arg_pattern)[1]).to eq('"personal"')
    end

    # A visibility: nested inside metadata: is captured with its closing
    # brace, which the literal check rejects — the scan then fails loud rather
    # than treating the row as personal.
    it "captures a nested metadata visibility: as a non-literal, not as personal" do
      call_args = %(action: "a.b", metadata: { visibility: "admin" }, visibility: "personal")
      expect(call_args.match(visibility_arg_pattern)[1]).not_to match(/\A["'][\w.]+["']\z/)
    end
  end

  it "labels every action either activity feed can render" do
    Rails.application.eager_load!
    trackable = ApplicationRecord.descendants.select { |model| model.include?(Trackable) }
    actions = trackable.flat_map { |model| %w[created updated].map { |verb| "#{model.model_name.param_key}.#{verb}" } }
    actions += %w[membership.deactivated membership.reactivated membership.left]
    # workspace.suspended/unsuspended are likewise derived by display_action
    # from workspace.updated's own changes metadata, never written by a
    # literal ActivityLog.create! — neither guard below can see them any
    # other way.
    actions += %w[workspace.suspended workspace.unsuspended]

    # No trailing `\(` — a paren-less call (gap: no parens) must still be
    # found so it can be reported, not silently missed. `(?=[\s(]|\z)`
    # anchors the boundary instead of `\b`, which `!?` backtracks past a
    # literal "!" (verified: `\bcreate!?\b` matches "create" and leaves "!("
    # unconsumed).
    write_call = /\bActivityLog\.create!?(?=[\s(]|\z)/
    literal_value = /\A["']([\w.]+)["']\z/
    # The one legitimate non-literal: Trackable#create_activity forwards its
    # caller's action rather than hardcoding one — already enumerated above
    # from the model descendants loop, so declared safe by exact value here
    # instead of silently allowed.
    declared_dynamic = { "app/models/concerns/trackable.rb" => [ "action" ] }.freeze

    unresolved = []

    SecurityEventWriters::ALLOWED.each_key do |relative|
      source = without_comments(File.read(Rails.root.join(relative)))
      position = 0
      while (match = write_call.match(source, position))
        line = source[0...match.begin(0)].count("\n") + 1
        position = match.end(0)

        paren = source[position..].match(/\A[ \t]*\(/)
        unless paren
          unresolved << "#{relative}:#{line}: ActivityLog write with no parentheses"
          next
        end

        open_index = position + paren[0].length - 1
        finish = balanced_end(source, open_index)
        unless finish
          unresolved << "#{relative}:#{line}: ActivityLog write whose parentheses never balance " \
            "(a `(` inside a string literal desyncs the depth count)"
          next
        end
        position = finish

        call_args = source[(open_index + 1)...(finish - 1)]
        action_match = call_args.match(action_arg_pattern)
        unless action_match
          unresolved << "#{relative}:#{line}: ActivityLog write with no resolvable action: argument " \
            "(a `)` inside an earlier string literal may have truncated the argument list)"
          next
        end

        raw_value = action_match[1]
        literal = raw_value.match(literal_value)
        if literal
          actions << literal[1]
        elsif !declared_dynamic[relative]&.include?(raw_value)
          unresolved << "#{relative}:#{line}: ActivityLog action `#{raw_value}` is not a string literal"
        end
      end
    end

    # A record_security_event! row reaches a feed only when a writer
    # overrides the personal default — a literal visibility: other than
    # "personal" — so the call site, not ActivityLog::SECURITY_ACTIONS, is
    # the source of truth for which actions need a feed label. No
    # visibility: argument, or a literal "personal", is an account-card row:
    # activity_log_spec's SECURITY_ACTIONS label check already guards it.
    # Receiver-anchored, like write_call above, so the writer's own `def`
    # line in activity_log.rb is not read as a call site.
    security_write = /\bActivityLog\.record_security_event!/
    Dir[Rails.root.join("app/**/*.rb")].each do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      raw = File.read(file)
      next unless raw.include?("record_security_event!")

      source = without_comments(raw)
      position = 0
      while (match = security_write.match(source, position))
        line = source[0...match.begin(0)].count("\n") + 1
        position = match.end(0)

        paren = source[position..].match(/\A[ \t]*\(/)
        unless paren
          unresolved << "#{relative}:#{line}: record_security_event! call with no parentheses"
          next
        end

        open_index = position + paren[0].length - 1
        finish = balanced_end(source, open_index)
        unless finish
          unresolved << "#{relative}:#{line}: record_security_event! call whose parentheses never balance"
          next
        end
        position = finish

        call_args = source[(open_index + 1)...(finish - 1)]
        visibility_match = call_args.match(visibility_arg_pattern)
        next unless visibility_match # no visibility: -> personal default -> account card, guarded elsewhere

        raw_visibility = visibility_match[1]
        visibility_literal = raw_visibility.match(literal_value)
        next if visibility_literal && visibility_literal[1] == "personal"

        unless visibility_literal
          unresolved << "#{relative}:#{line}: record_security_event! call with a non-literal visibility: argument"
          next
        end

        action_match = call_args.match(action_arg_pattern)
        unless action_match
          unresolved << "#{relative}:#{line}: record_security_event! call with a non-personal visibility " \
            "but no resolvable action: argument"
          next
        end

        raw_action = action_match[1]
        action_literal = raw_action.match(literal_value)
        if action_literal
          actions << action_literal[1]
        else
          unresolved << "#{relative}:#{line}: record_security_event! action `#{raw_action}` is not a string literal"
        end
      end
    end
    actions.uniq!

    expect(unresolved).to be_empty,
      "This scan reads app/ as text and cannot evaluate a non-literal action; each of these calls must " \
      "either use a literal action: string or have its exact value added to declared_dynamic above:\n  " \
      "#{unresolved.join("\n  ")}"

    missing = actions.reject { |action| I18n.exists?("activity.actions.#{action}") }

    expect(missing).to be_empty,
      "Feed actions without an activity.actions label:\n  #{missing.join("\n  ")}"
  end

  # The check must be able to fail.
  it "reports a member without a label" do
    expect(I18n.exists?("settings.sessions.activity.user.zz_unlabeled")).to be(false)
  end
end
