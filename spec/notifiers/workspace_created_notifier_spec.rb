# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceCreatedNotifier, type: :notifier do
  let(:creator) { create(:user) }

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
  end

  def events
    Noticed::Event.where(type: described_class.name)
  end

  # Workspace declares no `dependent:` for activity_logs and the FK blocks the
  # DELETE, so the audit rows go first. The placeholder contract is about the
  # record being gone, not about how it got there.
  def hard_delete(workspace)
    ActivityLog.where(workspace_id: workspace.id).delete_all
    workspace.destroy!
  end

  describe "declarations" do
    it "is :workspace_activity" do
      expect(described_class.category_name).to eq "workspace_activity"
    end

    it "declares severity :success" do
      expect(described_class.severity_name).to eq :success
    end
  end

  describe "trigger" do
    it "fires once for the creator when a workspace is created through the creation verb" do
      workspace = Workspace.create_owned({ name: "Acme" }, owner: creator)

      expect(events.count).to eq 1
      event = events.last
      expect(event.record).to eq(workspace)
      expect(event.notifications.map(&:recipient)).to eq([ creator ])
    end

    it "does not fire for a bare Workspace.create! (seeds, fixtures, factories)" do
      expect { create(:workspace) }.not_to change { events.count }
    end

    it "does not fire for the personal workspace auto-provisioned at signup" do
      expect { create(:user) }.not_to change { events.count }
    end

    it "does not fire when the workspace fails to save" do
      expect { Workspace.create_owned({ name: nil }, owner: creator) }.not_to change { events.count }
    end
  end

  describe "rendering" do
    it "names the workspace and carries the members-page url" do
      workspace = Workspace.create_owned({ name: "Acme" }, owner: creator)
      notification = events.last.notifications.first

      expect(notification.message).to eq(
        I18n.t("notifications.workspace_created.message", workspace: "Acme")
      )
      expect(notification.url).to eq(Rails.application.routes.url_helpers.workspace_members_path(workspace))
    end

    # `url` is linked from the digest email only — the in-app row
    # (settings/notifications/_item) renders the message, a timestamp and the
    # read/delete controls, and nothing else. Copy that names a page is
    # therefore a promise the row itself cannot keep.
    it "promises no destination the in-app row cannot reach" do
      workspace = Workspace.create_owned({ name: "Acme" }, owner: creator)
      notification = events.last.notifications.first

      expect(notification.message).not_to match(/\bpage\b/i)
    end

    # The record IS the routed object here, so a deleted workspace hands the
    # helper a bare nil — ActionController::UrlGenerationError, which
    # render_safe_or_placeholder deliberately does not rescue. Unrescued it
    # takes down the whole digest render for this user, not just this row.
    it "returns the placeholder copy when the workspace has been deleted" do
      workspace = Workspace.create_owned({ name: "Acme" }, owner: creator)
      notification = events.last.notifications.first
      hard_delete(workspace)

      expect(notification.reload.url).to eq(I18n.t("notifications.placeholder"))
    end

    it "returns the placeholder copy for the message too when the workspace has been deleted" do
      workspace = Workspace.create_owned({ name: "Acme" }, owner: creator)
      notification = events.last.notifications.first
      hard_delete(workspace)

      expect(notification.reload.message).to eq(I18n.t("notifications.placeholder"))
    end
  end

  describe "preference gating" do
    it "skips in-app when the creator disables the workspace_activity category" do
      prefs = create(:user_preferences, user: creator)
      np = prefs.notification_preferences.deep_dup
      np["notification_types"]["workspace_activity"] = false
      prefs.update!(notification_preferences: np)

      Workspace.create_owned({ name: "Acme" }, owner: creator)

      expect(Noticed::Notification.where(recipient: creator,
                                         type: "#{described_class.name}::Notification").count).to eq 0
    end
  end
end
