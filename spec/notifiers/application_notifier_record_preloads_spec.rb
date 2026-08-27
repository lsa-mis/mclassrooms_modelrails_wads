# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationNotifier, "record preloads" do
  describe ".record_preloads DSL" do
    it "defaults to an empty spec" do
      stub_const("BareNotifier", Class.new(ApplicationNotifier))

      expect(BareNotifier.record_preload_spec).to eq([])
    end

    it "stores the declared association tree on the subclass" do
      stub_const("DeclaringNotifier", Class.new(ApplicationNotifier) do
        record_preloads :project
      end)

      expect(DeclaringNotifier.record_preload_spec).to eq([ :project ])
    end

    it "accepts the nested hash form for polymorphic hops" do
      stub_const("NestedNotifier", Class.new(ApplicationNotifier) do
        record_preloads :accepted_by, invitable: :workspace
      end)

      expect(NestedNotifier.record_preload_spec).to eq([ :accepted_by, { invitable: :workspace } ])
    end

    it "does not leak a subclass declaration onto the base class" do
      stub_const("LeakProbeNotifier", Class.new(ApplicationNotifier) do
        record_preloads :project
      end)

      expect(ApplicationNotifier.record_preload_spec).to eq([])
    end
  end

  describe ".preload_records" do
    let(:recipient) { create(:user) }

    def reloaded_notifications_for(recipient)
      # Mirrors the index's base includes — the pipeline's own preloads are
      # what the examples assert on top of it.
      recipient.notifications.includes(event: :record).order(created_at: :desc).to_a
    end

    it "preloads each declared association on the polymorphic records" do
      # Fork: Membership via WorkspaceMemberAddedNotifier (record_preloads
      # :user, :workspace) — the plain-association shape.
      2.times do
        membership = create(:membership, user: create(:user))
        WorkspaceMemberAddedNotifier.with(record: membership).deliver(recipient)
      end
      notifications = reloaded_notifications_for(recipient)

      ApplicationNotifier.preload_records(notifications)

      records = notifications.map { _1.event.record }
      expect(records).to all(satisfy { _1.association(:user).loaded? })
      expect(records).to all(satisfy { _1.association(:workspace).loaded? })
    end

    it "walks nested declarations, skipping invitable classes without the association" do
      # Fork: invitable is always a Workspace, which has no :workspace
      # association — so one invitation exercises both halves of the
      # declaration (invitable: :workspace): the invitable hop loads, the
      # nested hop is skipped without raising.
      workspace_invitation = create(:invitation, invitable: create(:workspace), email: recipient.email_address)
# ExpiringSoon dropped its nested declaration when its copy went neutral
      # (it no longer traverses to the workspace), so the nested-walk case needs
      # a notifier that still declares one.
      WorkspaceInvitationResentNotifier.with(record: workspace_invitation).deliver(recipient)
      notifications = reloaded_notifications_for(recipient)

      expect { ApplicationNotifier.preload_records(notifications) }.not_to raise_error

      expect(notifications.map(&:event).map(&:record)).to all(satisfy { _1.association(:invitable).loaded? })
    end

    it "is a no-op for notifiers with no declaration" do
      PasswordChangedNotifier.with(record: recipient).deliver(recipient)
      # No `event: :record` include here: this example never renders a
      # message, so an eager-loaded record would trip Bullet's unused-eager-
      # loading check — an artifact of the unit spec, not the page.
      notifications = recipient.notifications.includes(:event).to_a

      expect { ApplicationNotifier.preload_records(notifications) }.not_to raise_error
    end

    it "tolerates a mixed page of declared and undeclared notifier types" do
      PasswordChangedNotifier.with(record: recipient).deliver(recipient)
      membership = create(:membership, user: create(:user))
      WorkspaceMemberAddedNotifier.with(record: membership).deliver(recipient)
      notifications = reloaded_notifications_for(recipient)

      ApplicationNotifier.preload_records(notifications)
      # Touch every record the way the page's message renders do, so
      # Bullet judges the eager loads as used — mirrors the real index.
      notifications.each { _1.event.record }

      added = notifications.find { _1.event.type == "WorkspaceMemberAddedNotifier" }
      expect(added.event.record.association(:workspace)).to be_loaded
    end
  end
end
