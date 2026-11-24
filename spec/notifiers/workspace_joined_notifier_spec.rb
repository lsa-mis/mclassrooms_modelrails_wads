# frozen_string_literal: true

require "rails_helper"

# The self-join paths have no granter: the joining user is the actor. So
# WorkspaceMemberAddedNotifier must exclude them (nobody is notified about their
# own action) — otherwise a self-joiner reads "Grace joined Ada's Workspace"
# about herself. Whether they get an orientation notice in its place depends on
# the self_join grade, and both onboarding presets are pinned here too.
RSpec.describe "Self-join notifications", type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  def member_role
    build(:membership).role
  end

  def self_join_cast
    owner = create(:user)
    joiner = create(:user)
    workspace = create(:workspace)
    create(:membership, :owner, user: owner, workspace: workspace)
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    { workspace: workspace, owner: owner, joiner: joiner }
  end

  def member_added_recipients
    Noticed::Notification.where(type: "WorkspaceMemberAddedNotifier::Notification").map(&:recipient)
  end

  def joined_notifications_for(user)
    Noticed::Notification.where(recipient: user, type: "WorkspaceJoinedNotifier::Notification")
  end

  describe "a fresh self-join" do
    it "does not notify the self-joiner about their own join" do
      workspace, joiner = self_join_cast.values_at(:workspace, :joiner)
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(member_added_recipients).not_to include(joiner)
    end

    it "still notifies the workspace owners that someone joined" do
      workspace, owner, joiner = self_join_cast.values_at(:workspace, :owner, :joiner)
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(member_added_recipients).to contain_exactly(owner)
    end

    it "sends the self-joiner exactly one orientation notification" do
      workspace, joiner = self_join_cast.values_at(:workspace, :joiner)
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(joined_notifications_for(joiner).count).to eq 1
    end

    it "orients them with the workspace name and carries the workspace url" do
      workspace, joiner = self_join_cast.values_at(:workspace, :joiner)
      workspace.admit(joiner, role: member_role, self_join: true)
      notification = joined_notifications_for(joiner).sole

      expect(notification.message).to eq(
        I18n.t("notifications.workspace_joined.message", workspace_name: workspace.name)
      )
      expect(notification.url).to eq(Rails.application.routes.url_helpers.workspace_path(workspace))
    end

    # `url` is linked from the digest email only — the in-app row
    # (settings/notifications/_item) renders the message, a timestamp and the
    # read/delete controls, and nothing else. Copy that names a page is
    # therefore a promise the row itself cannot keep.
    it "promises no destination the in-app row cannot reach" do
      workspace, joiner = self_join_cast.values_at(:workspace, :joiner)
      workspace.admit(joiner, role: member_role, self_join: true)
      notification = joined_notifications_for(joiner).sole

      expect(notification.message).not_to match(/\bpage\b/i)
    end

    # Mirrors the invitation notifiers' deleted-record url examples: the row
    # outlives the membership it points at, and neither #message nor #url may
    # raise out of the notifications index or the digest render.
    it "renders the placeholder for both message and url once the membership is gone" do
      workspace, joiner = self_join_cast.values_at(:workspace, :joiner)
      workspace.admit(joiner, role: member_role, self_join: true)
      notification = joined_notifications_for(joiner).sole
      workspace.memberships.find_by!(user: joiner).destroy

      expect(notification.reload.message).to eq(I18n.t("notifications.placeholder"))
      expect(notification.url).to eq(I18n.t("notifications.placeholder"))
    end

    it "does not notify the owners about the joiner's own orientation" do
      workspace, owner, joiner = self_join_cast.values_at(:workspace, :owner, :joiner)
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(joined_notifications_for(owner).count).to eq 0
    end

    it "sends no email at all — the joiner is already in the app, the owners are digest-only" do
      workspace, joiner = self_join_cast.values_at(:workspace, :joiner)
      workspace.admit(joiner, role: member_role, self_join: true)
      drain_noticed_jobs(deliver_mail: true)

      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "honours the in-app preference for the workspace_activity category" do
      workspace, joiner = self_join_cast.values_at(:workspace, :joiner)
      prefs = create(:user_preferences, user: joiner)
      types = prefs.notification_preferences.deep_dup
      types["notification_types"]["workspace_activity"] = false
      prefs.update!(notification_preferences: types)

      workspace.admit(joiner, role: member_role, self_join: true)

      expect(joined_notifications_for(joiner).count).to eq 0
    end

    # The provenance question: nobody granted an open-link join. Recording the
    # joiner as their own granter would make a self-join indistinguishable from
    # an admin grant in the audit trail.
    it "records no grant provenance on the membership.created activity row" do
      workspace, joiner = self_join_cast.values_at(:workspace, :joiner)
      workspace.admit(joiner, role: member_role, self_join: true)
      membership = workspace.memberships.find_by!(user: joiner)
      entry = ActivityLog.where(action: "membership.created", trackable: membership).last

      expect(entry.metadata).not_to have_key("granted_by")
    end
  end

  describe "a removed member self-joining again" do
    def deactivate_joiners_membership(workspace, joiner)
      create(:membership, user: joiner, workspace: workspace).deactivate!
      Noticed::Notification.delete_all
      Noticed::Event.delete_all
    end

    it "excludes the self-joiner from member-added but still notifies the owners" do
      workspace, owner, joiner = self_join_cast.values_at(:workspace, :owner, :joiner)
      deactivate_joiners_membership(workspace, joiner)
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(member_added_recipients).to contain_exactly(owner)
    end

    it "sends the self-joiner exactly one orientation notification" do
      workspace, joiner = self_join_cast.values_at(:workspace, :joiner)
      deactivate_joiners_membership(workspace, joiner)
      workspace.admit(joiner, role: member_role, self_join: true)

      expect(joined_notifications_for(joiner).count).to eq 1
    end
  end

  # Not in scope, and it must stay that way: an invitee is not the actor.
  describe "the invited-member path (unchanged)" do
    it "keeps the added user in member-added and raises no orientation notification" do
      workspace, owner, joiner = self_join_cast.values_at(:workspace, :owner, :joiner)
      workspace.admit(joiner, role: member_role, granted_by: owner)

      expect(member_added_recipients).to contain_exactly(joiner)
      expect(joined_notifications_for(joiner).count).to eq 0
    end
  end

  # User#create_personal_workspace also creates a Membership directly and sets
  # no marker — correctly, because the first owner has nobody to tell. The
  # workspace_has_other_owners? guard is what keeps it silent; pinned here so
  # the Guard A allow-list entry for that call site stays falsifiable.
  describe "the :personal preset's signup workspace" do
    it "raises no membership notification for the first owner" do
      newcomer = create(:user)

      expect(newcomer.personal_workspace_id).to be_present
      expect(member_added_recipients).to be_empty
      expect(joined_notifications_for(newcomer)).to be_empty
    end
  end

  # The :shared preset's signup join (User#join_shared_workspace) bypasses
  # Workspace#admit and creates the membership directly, so it needs the same
  # actor stance declared explicitly. Its orientation notice is deliberately
  # suppressed — see the :onboarding grade on Membership#self_join.
  describe "the :shared preset's signup join" do
    def stub_shared_preset(workspace)
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
      allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    end

    it "does not tell the new user, in the third person, that they joined" do
      workspace = self_join_cast.fetch(:workspace)
      stub_shared_preset(workspace)
      newcomer = create(:user)

      expect(member_added_recipients).not_to include(newcomer)
    end

    it "still tells the shared workspace's owners that someone joined" do
      workspace, owner = self_join_cast.values_at(:workspace, :owner)
      stub_shared_preset(workspace)
      create(:user)

      expect(member_added_recipients).to contain_exactly(owner)
    end

    it "raises no orientation notice — WelcomeNotifier already covers day one" do
      workspace = self_join_cast.fetch(:workspace)
      stub_shared_preset(workspace)
      newcomer = create(:user)

      expect(joined_notifications_for(newcomer)).to be_empty
    end
  end
end
