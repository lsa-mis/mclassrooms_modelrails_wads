require "rails_helper"

# Invariant I3 of the decline-and-block feature (PR 4): the inviter must never
# be able to confirm a block. `Invitation#record_suppressed_delivery` writes
# the ONLY evidence of a suppressed delivery, and deliberately gives it
# `visibility: "admin"` so it drops out of every inviter-facing feed. That
# safety was established by inspection alone (#913) — nothing asserted it, and
# the inviter is frequently a workspace owner or admin, precisely the
# "admin"-tier audience. This spec makes the property durable: it fails the
# day any of these three read surfaces starts rendering admin rows, rather
# than waiting for an admin console to ship the oracle.
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
end
