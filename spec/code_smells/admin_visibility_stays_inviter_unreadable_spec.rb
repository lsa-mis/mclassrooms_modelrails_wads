require "rails_helper"

# Invariant I3 (security.md, Invitation blocks): an inviter must never read the
# admin-visibility suppression row (#913). Fails if any read surface shows admin rows.
RSpec.describe "Code smell: invitation.delivery_suppressed stays admin-only" do
  let(:workspace) { create(:workspace) }
  let(:inviter) { create(:user) }
  let(:invitation) do
    create(:invitation, invitable: workspace, invited_by: inviter, email: "blocked@example.com")
  end

  let!(:suppressed_row) do
    create(:activity_log,
           actor: nil,
           action: "invitation.delivery_suppressed",
           trackable: invitation,
           workspace: workspace,
           visibility: "admin",
           metadata: { "mailer_action" => "invite" })
  end

  # Positive control on the same trackable/workspace: proves the relations
  # below actually filter on visibility rather than passing because nothing
  # matches at all — a guard trivially green for the wrong reason is worse
  # than none (project convention: verify enumerables before publishing).
  let!(:visible_row) do
    create(:activity_log,
           action: "invitation.resent",
           trackable: invitation,
           workspace: workspace,
           visibility: "workspace")
  end

  it "never appears in ActivityLog.visible" do
    expect(ActivityLog.visible).to include(visible_row)
    expect(ActivityLog.visible).not_to include(suppressed_row)
  end

  it "never appears in the feed's own .visible.for_workspace composition" do
    expect(ActivityLog.visible.for_workspace(workspace)).to include(visible_row)
    expect(ActivityLog.visible.for_workspace(workspace)).not_to include(suppressed_row)
  end

  it "never appears in ActivityLog.security_events_for the inviter" do
    expect(ActivityLog.security_events_for(inviter)).not_to include(suppressed_row)
  end

  # The operations feed is the admin console this spec's header anticipated.
  # On a :shared instance the bootstrap owner is BOTH the operator and the
  # inviter, so an admin-tier surface is an inviter-facing one and I3 is a
  # question about this scope, not only about the workspace feeds.
  it "never appears in ActivityLog.for_operations_feed" do
    expect(ActivityLog.for_operations_feed).to include(visible_row)
    expect(ActivityLog.for_operations_feed).not_to include(suppressed_row)
  end

  # Naming the surfaces is what let the console ship past this guard: a scope
  # added later is invisible to a list of examples. Enumerate the read-surface
  # scopes instead and fail on any this spec does not cover, so the next one
  # cannot be added silently.
  it "covers every read-surface scope ActivityLog defines" do
    covered = %w[visible security_events_for for_operations_feed]
    # for_workspace and recent are composable fragments, not read surfaces:
    # neither filters visibility, and both are always chained onto one above.
    # The ledger's five filters are the same shape: of_kind narrows the action
    # prefix, involving the actor/subject, matching_any the records the search
    # box resolved, within the created_at window, oldest_first only reorders,
    # at_instance_level only drops workspace rows.
    # by_workspace_name is the same shape as oldest_first: a reorder (plus the
    # left join it orders on), no predicate of its own.
    # None reads `visibility`, and Operations::ActivityLogsController chains
    # every one of them onto for_operations_feed, which is covered above.
    fragments = %w[
      for_workspace recent
      of_kind involving matching_any within oldest_first at_instance_level
      by_workspace_name
    ]

    declared = File.read(Rails.root.join("app/models/activity_log.rb"))
                   .scan(/^  scope :(\w+)/).flatten

    expect(declared - covered - fragments).to be_empty, <<~MESSAGE
      New ActivityLog scope(s) not covered by invariant I3:
        #{(declared - covered - fragments).join(', ')}
      If the scope is a reader-facing surface, add an example proving a
      delivery-suppressed row cannot reach it. If it is a composable fragment
      that never filters visibility on its own, add it to `fragments` and say
      why. Do not add it to `covered` without an example.
    MESSAGE
  end
end
