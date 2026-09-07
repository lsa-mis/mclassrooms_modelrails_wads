# frozen_string_literal: true

require "rails_helper"

# Every membership creation has an actor, and the notification fan-out keys off
# it: nobody is notified about their own action, so `WorkspaceMemberAddedNotifier`
# excludes whoever performed the add. The actor reaches it through exactly two
# non-persisted markers on `Membership` — `granted_by` (someone granted this)
# and `self_join` (nobody did; the joining user acted).
#
# A call site that names neither is not neutral, it is wrong-by-default: the
# actor resolves to `nil`, nobody is excluded, and the new member is told in the
# third person that they joined. That is exactly what `User#join_shared_workspace`
# did — it bypassed `Workspace#admit`, set no marker, and handed a brand-new
# user "Grace joined Acme" about herself. Nothing failed; the suite stayed green.
#
# So the rule is declaration, not correctness: a creation site must SAY which
# stance it takes, or be a reviewed exception below. Going through
# `Workspace#admit` satisfies it, because admit forwards both markers.
#
# Scanned shape: `create`/`create!`/`insert_all`/`upsert_all` on a `memberships`
# association or on `Membership` itself. A `memberships.build` + `save` pair
# would slip past — if that shape ever appears, widen the pattern rather than
# adding the site to the allow-list.
RSpec.describe "Code smell: membership creation declares its actor stance" do
  # Locals, not constants: a constant here lands on Object, where another spec
  # file's same-named constant clobbers it whenever CI shards both into one
  # worker.
  creation_call = /\b(?:memberships|Membership)\.(?:create!?|insert_all!?|upsert_all!?)\s*\(/

  stance_argument = /\b(?:granted_by|self_join):/

  # "path#method" => why this site legitimately declares no actor stance.
  # Both are first-owner seeds: the membership being created IS the workspace's
  # only owner, so `Membership#workspace_has_other_owners?` is false and
  # `notify_member_added` never runs. There is nobody to notify and therefore
  # no actor to exclude. Pinned by the ":personal preset's signup workspace"
  # example in spec/notifiers/workspace_joined_notifier_spec.rb, so this
  # exemption stays falsifiable rather than merely asserted.
  allowed_without_stance = {
    "app/models/user/onboarding.rb#create_personal_workspace" =>
      "seeds the very first owner of a just-created personal workspace",
    "app/models/workspace.rb#create_owned" =>
      "seeds the very first owner of a just-created workspace"
  }.freeze

  def ruby_sources
    Dir[Rails.root.join("{app,lib}/**/*.rb")]
  end

  # without_comments / balanced_end come from spec/support/source_scanning.rb,
  # shared with the recipients-block fence.
  def enclosing_method(source, index)
    source[0...index].scan(/^\s*def\s+(?:self\.)?([\w?!]+)/).last&.first || "(top level)"
  end

  # [site, line, snippet, arguments] for every membership creation in app/lib.
  def creation_sites(pattern)
    ruby_sources.flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      source = without_comments(File.read(file))
      found = []
      position = 0

      while (match = pattern.match(source, position))
        position = match.end(0)
        finish = balanced_end(source, match.end(0) - 1)
        next unless finish

        found << [
          "#{relative}##{enclosing_method(source, match.begin(0))}",
          source[0...match.begin(0)].count("\n") + 1,
          match[0].strip,
          source[match.end(0)...(finish - 1)]
        ]
      end

      found
    end
  end

  it "every membership-creation site names granted_by or self_join" do
    offenders = creation_sites(creation_call).filter_map do |site, line, snippet, arguments|
      next if allowed_without_stance.key?(site)
      next if arguments.match?(stance_argument)

      "#{site} (line #{line}): #{snippet}"
    end

    expect(offenders).to be_empty,
      "A Membership created without `granted_by:` or `self_join:` leaves the " \
      "notification actor nil, so nobody is excluded from " \
      "WorkspaceMemberAddedNotifier and the new member is told about their own " \
      "join. Route the creation through Workspace#admit, or pass the marker " \
      "that says who acted. Undeclared creation sites found:\n  " \
      "#{offenders.join("\n  ")}\nA site with genuinely no actor to exclude " \
      "belongs in allowed_without_stance in this spec, with its reason."
  end

  it "carries no stale exemptions" do
    live_sites = creation_sites(creation_call).map(&:first).uniq
    stale = allowed_without_stance.keys - live_sites

    expect(stale).to be_empty,
      "These exemptions name a site that no longer creates a Membership — the " \
      "allow-list is describing code that moved or went away, and would silently " \
      "cover a future site that reuses the name:\n  #{stale.join("\n  ")}"
  end
end
