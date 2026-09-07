# frozen_string_literal: true

require "rails_helper"

# The N+1 guard for the notifications index. One request renders TWO
# notifications of EVERY notifier type while Bullet raises — two of each
# because Bullet only flags an association lazy-loaded on 2+ instances.
# A notifier whose `#message` traverses an association missing from its
# `record_preloads` declaration fails here; a superfluous declaration fails
# as unused eager loading. The roster check keeps this honest for forks:
# add app/notifiers/foo_notifier.rb and this spec fails until notifier_types
# and `deliver_roster_to(user)` cover it (and the notifier declares
# `record_preloads`, if its `#message` traverses off the record).
RSpec.describe "Settings::Notifications record-preload guard", type: :request do
  def notifier_types
    %w[
      PasskeyAddedNotifier
      PasswordChangedNotifier
      SignInFromNewDeviceNotifier
      WorkspaceCapacityApproachingNotifier
      WorkspaceCreatedNotifier
      WorkspaceJoinedNotifier
      WorkspaceMemberAddedNotifier
      WorkspaceMemberRemovedNotifier
      WorkspaceRoleChangedNotifier
      WorkspaceInvitationAcceptedNotifier
      WorkspaceInvitationDeclinedNotifier
      WorkspaceInvitationExpiringSoonNotifier
      WorkspaceInvitationResentNotifier
      WelcomeNotifier
    ]
  end

  let(:user) { create(:user) }

  before { sign_in(user) }

  # Same-bucket collisions dedup-drop a repeat dispatch (see the idempotency
  # machinery in ApplicationNotifier) — space delivery rounds apart in time.
  def in_distinct_idempotency_bucket(&block)
    @notification_offset = (@notification_offset || 0) + 5
    travel_to(Time.current + @notification_offset.minutes, &block)
  end

  # Fork: plain workspace invitations (no client invitations here).
  def roster_invitation(overrides = {})
    create(:invitation, { email: "guard-#{SecureRandom.hex(4)}@example.test" }.merge(overrides))
  end

  def owner_role
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_settings: true }
    end
  end

  # One notification of every type per call.
  #
  # Deliberate: the block-declaring notifiers below are handed an explicit
  # `user`, which bypasses their `recipients` block and its preference gating.
  # App code must never do this (spec/code_smells/notifier_recipients_block_dispatch_spec.rb
  # fences app/ for exactly that) — here it is what makes the roster
  # deterministic: every type must land one row for this user regardless of
  # preferences, or the page under test loses the type it is meant to render.
  def deliver_roster_to(user, round:)
    in_distinct_idempotency_bucket do
      PasskeyAddedNotifier.with(record: user).deliver(user)
      PasswordChangedNotifier.with(record: user).deliver(user)
      SignInFromNewDeviceNotifier
        .with(record: user, user_agent: "Guard UA #{round}", os: "macOS").deliver(user)

      # A bare factory workspace has no other owners, so membership creation
      # skips its notify_member_added callback — deliver explicitly.
      workspace = create(:workspace)
      membership = create(:membership, user: user, workspace: workspace, role: owner_role)
      WorkspaceMemberAddedNotifier.with(record: membership).deliver(user)
      WorkspaceMemberRemovedNotifier.with(record: membership, actor: nil).deliver(user)
      WorkspaceJoinedNotifier.with(record: membership).deliver(user)
      WorkspaceCapacityApproachingNotifier
        .with(record: workspace, metric: :members, current: 8, limit: 10).deliver(user)
      WorkspaceCreatedNotifier.with(record: workspace, creator: user).deliver(user)
      WorkspaceRoleChangedNotifier.with(record: membership).deliver(user)

      WorkspaceInvitationAcceptedNotifier
        .with(record: roster_invitation(accepted_by: create(:user))).deliver(user)
      WorkspaceInvitationDeclinedNotifier.with(record: roster_invitation).deliver(user)
      WorkspaceInvitationExpiringSoonNotifier.with(record: roster_invitation).deliver(user)
      WorkspaceInvitationResentNotifier.with(record: roster_invitation).deliver(user)
      WelcomeNotifier.with(record: user).deliver(user)
    end
  end

  def categories_in_roster
    notifier_types.map { _1.constantize.category_name }.uniq
  end

  it "keeps the roster in sync with app/notifiers" do
    on_disk = Dir[Rails.root.join("app/notifiers/*_notifier.rb").to_s]
      .map { File.basename(_1, ".rb").camelize }
      .reject { _1 == "ApplicationNotifier" }

    expect(notifier_types).to match_array(on_disk)
  end

  it "renders two of every notifier type without an N+1" do
    2.times { |round| deliver_roster_to(user, round: round) }

    # One request per category rather than one for the whole roster: page 1
    # caps at 25 rows and two of every type outgrew that when WelcomeNotifier
    # made thirteen. Each request is still a mixed page for its category, and
    # still carries TWO of every type it renders — which is what Bullet needs.
    bodies = categories_in_roster.index_with do |category|
      rows = user.notifications.where(type: ApplicationNotifier.notification_types_for(category)).count
      expect(rows).to be <= 25,
        "the #{category} slice delivers #{rows} notifications — page 1 caps at 25, so some types would escape the guard"

      get settings_notifications_path(category: category)
      expect(response).to have_http_status(:ok)
      response.body
    end

    notifier_types.each do |notifier_class|
      body = bodies.fetch(notifier_class.constantize.category_name)
      # At least, not exactly: ambient dispatches (sign_in itself notifies
      # SignInFromNewDevice) can add a third row, which only strengthens
      # the guard.
      expect(body.scan("data-notification-type=\"#{notifier_class}::Notification\"").size)
        .to be >= 2, "expected at least two rendered #{notifier_class} notifications"
    end
  end
end
