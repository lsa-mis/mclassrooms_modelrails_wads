require "rails_helper"

RSpec.describe NotificationBellHelper, type: :helper do
  let(:user) { create(:user) }
  let(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_settings: true }
    end
  end

  describe "#unread_notification_summary" do
    it "returns count 0 and nil severity when there are no unread notifications" do
      expect(helper.unread_notification_summary(user)).to eq(count: 0, severity: nil)
    end

    it "returns the total count and the highest severity present" do
      # danger
      PasswordChangedNotifier.with(record: user).deliver(user)

      # warning — user must be a workspace owner to receive
      warning_workspace = create(:workspace)
      create(:membership, user: user, workspace: warning_workspace, role: owner_role)
      WorkspaceCapacityApproachingNotifier
        .with(record: warning_workspace, metric: :members, current: 8, limit: 10)
        .deliver(user)

      # success — added_user is the added Membership.user
      success_workspace = create(:workspace)
      added_membership = create(:membership, user: user, workspace: success_workspace)
      WorkspaceMemberAddedNotifier.with(record: added_membership).deliver(user)

      result = helper.unread_notification_summary(user)
      expect(result[:count]).to eq(3)
      expect(result[:severity]).to eq(:danger)
    end

    it "ranks warning above info above success" do
      warning_workspace = create(:workspace)
      create(:membership, user: user, workspace: warning_workspace, role: owner_role)
      WorkspaceCapacityApproachingNotifier
        .with(record: warning_workspace, metric: :members, current: 8, limit: 10)
        .deliver(user)

      invitation = create(:invitation, email: user.email_address)
      WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)

      result = helper.unread_notification_summary(user)
      expect(result[:severity]).to eq(:warning)
    end

    it "defaults to :info severity when a notifier class is missing" do
      # Simulate orphaned notifier row by stubbing the breakdown directly.
      allow(user).to receive(:unread_notification_breakdown).and_return("DeletedNotifier" => 1)
      expect(Rails.logger).to receive(:warn).with(/Stale notifier class.*DeletedNotifier/)

      result = helper.unread_notification_summary(user)
      expect(result[:severity]).to eq(:info)
      expect(result[:count]).to eq(1)
    end

    it "logs a warning for each stale notifier class and resolves around them" do
      # Mixes two stale classes with a valid one to prove the resolver doesn't
      # short-circuit on the first stale class and still computes the highest
      # severity across the remaining valid notifier(s). WorkspaceMemberAdded
      # is severity :success; stale classes fall back to :info. :info ranks
      # higher than :success in SEVERITY_RANK, so :info wins.
      allow(user).to receive(:unread_notification_breakdown).and_return(
        "DeletedNotifierA"             => 1,
        "DeletedNotifierB"             => 2,
        "WorkspaceMemberAddedNotifier" => 1
      )

      expect(Rails.logger).to receive(:warn).with(/Stale notifier class.*DeletedNotifierA/)
      expect(Rails.logger).to receive(:warn).with(/Stale notifier class.*DeletedNotifierB/)

      result = helper.unread_notification_summary(user)

      expect(result[:severity]).to eq(:info)
      expect(result[:count]).to eq(4)
    end
  end

  describe "#notification_bell_classes" do
    it "returns text-danger with dark:text-danger-strong override for :danger" do
      expect(helper.notification_bell_classes(:danger)).to eq(icon: "text-danger dark:text-danger-strong")
    end

    it "returns the info classes for an unknown severity" do
      expect(helper.notification_bell_classes(:unknown)).to eq(icon: "text-info")
    end

    {
      warning: { icon: "text-warning" },
      info:    { icon: "text-info"    },
      success: { icon: "text-success" }
    }.each do |severity, classes|
      it "returns the expected classes for #{severity.inspect}" do
        expect(helper.notification_bell_classes(severity)).to eq(classes)
      end
    end

    describe "variant: :dot — for the avatar notification indicator" do
      # Calibrated for WCAG 1.4.11 non-text-contrast 3:1 (graphics target),
      # NOT 1.4.6 text 7:1. The indicator dot is decorative; severity meaning
      # is also exposed in the user-menu Notifications row aria-live region.
      it "returns bg-danger-strong + pulse:true for :danger" do
        expect(helper.notification_bell_classes(:danger, variant: :dot))
          .to eq(bg: "bg-danger-strong", pulse: true)
      end

      it "returns bg-warning + pulse:false for :warning" do
        expect(helper.notification_bell_classes(:warning, variant: :dot))
          .to eq(bg: "bg-warning", pulse: false)
      end

      it "returns bg-info + pulse:false for :info" do
        expect(helper.notification_bell_classes(:info, variant: :dot))
          .to eq(bg: "bg-info", pulse: false)
      end

      it "falls back to :info classes for an unknown severity" do
        expect(helper.notification_bell_classes(:unknown, variant: :dot))
          .to eq(bg: "bg-info", pulse: false)
      end

      # Existing call sites pass severity without keyword arg; their behavior
      # must be unchanged (regression guard for the :icon variant default).
      it "defaults to :icon variant when variant kwarg is omitted" do
        expect(helper.notification_bell_classes(:danger))
          .to eq(icon: "text-danger dark:text-danger-strong")
      end
    end
  end

  describe "#canonical_severity" do
    it "returns the severity unchanged when it's canonical" do
      %i[danger warning info success].each do |sev|
        expect(helper.canonical_severity(sev)).to eq(sev)
      end
    end

    it "falls back to :info for off-canonical severities" do
      expect(helper.canonical_severity(:critical)).to eq(:info)
      expect(helper.canonical_severity(nil)).to eq(:info)
      expect(helper.canonical_severity(:made_up)).to eq(:info)
    end
  end

  describe "#avatar_button_aria_label" do
    it "returns the plain label when there are no unread notifications" do
      expect(helper.avatar_button_aria_label(user)).to eq("User menu for #{user.full_name}")
    end

    it "includes count and severity phrase when unread > 0" do
      PasswordChangedNotifier.with(record: user).deliver(user)

      label = helper.avatar_button_aria_label(user)
      expect(label).to include("1 unread notification,")
      expect(label).not_to include("1 unread notifications")
      expect(label).to include("a security alert")
    end

    it "uses the plural form when unread > 1" do
      3.times do |i|
        PasswordChangedNotifier.with(record: user, idempotency_key: "k_#{i}").deliver(user)
      end

      label = helper.avatar_button_aria_label(user)
      expect(label).to include("3 unread notifications")
    end

    # Pins the explicit-summary contract used by the view partials and by
    # NotificationBroadcaster. When the caller has already computed the
    # summary, we MUST NOT re-query the user's unread breakdown.
    it "accepts an explicit summary argument (skips the re-query)" do
      precomputed = { count: 0, severity: nil }
      expect(user).not_to receive(:unread_notification_breakdown)
      expect(helper.avatar_button_aria_label(user, precomputed)).to eq("User menu for #{user.full_name}")
    end

    it "uses the explicit summary's severity phrase when unread > 0" do
      precomputed = { count: 5, severity: :warning }
      expect(user).not_to receive(:unread_notification_breakdown)
      label = helper.avatar_button_aria_label(user, precomputed)
      expect(label).to include("5 unread notifications")
      expect(label).to include("an important update")
    end
  end

  # Pins the module-level entry points used by callers outside the view
  # context (currently NotificationBroadcaster, which has no view-helper
  # mixin and must call NotificationBellHelper.<method> directly).
  describe "module-level entry points (for NotificationBroadcaster)" do
    let(:summary_user) { create(:user) }

    it "exposes unread_notification_summary as a module method" do
      expect(NotificationBellHelper.unread_notification_summary(summary_user)).to eq(count: 0, severity: nil)
    end

    it "exposes notification_bell_classes as a module method" do
      expect(NotificationBellHelper.notification_bell_classes(:danger)).to eq(icon: "text-danger dark:text-danger-strong")
    end
  end
end
