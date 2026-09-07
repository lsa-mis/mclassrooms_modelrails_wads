require "rails_helper"

# Membership::Announcements's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe Membership, type: :model do
  # Wiring coverage: drive the model state change and assert the notifier
  # actually fires. The notifiers themselves are specced in spec/notifiers/;
  # without these, the after_*_commit registrations could be deleted and the
  # suite would stay green.
  describe "notification wiring" do
    let(:owner) { create(:user) }
    let(:workspace) { create(:workspace) }
    let!(:owner_membership) { create(:membership, :owner, user: owner, workspace: workspace) }
    let(:member) { create(:user) }

    describe "member added (after_create_commit)" do
      it "notifies the added user and the existing owner" do
        membership = create(:membership, user: member, workspace: workspace)
        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event).to be_present
        expect(event.record).to eq(membership)
        expect(event.notifications.map(&:recipient)).to contain_exactly(member, owner)
      end

      it "does not notify when seeding a workspace's first owner" do
        fresh_workspace = create(:workspace)
        expect {
          create(:membership, :owner, user: member, workspace: fresh_workspace)
        }.not_to change { Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").count }
      end

      it "excludes the actor who performed the add" do
        workspace.admit(member, role: Role.system_default!("member"), granted_by: owner)
        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end

      # #935: this fan-out is best-effort — a raising notifier must not turn a
      # committed membership into a 500.
      it "still adds the member when the notifier raises" do
        allow(WorkspaceMemberAddedNotifier).to receive(:with).and_raise(StandardError, "boom")
        expect(Rails.error).to receive(:report).with(
          kind_of(StandardError),
          hash_including(handled: true, context: hash_including(action: "member_added"))
        )

        membership = nil
        expect {
          membership = create(:membership, user: member, workspace: workspace)
        }.not_to raise_error
        expect(membership.reload).to be_persisted
      end
    end

    # #933: removal was the one membership transition that notified nobody.
    # Covered here rather than in the notifier spec because these pin the
    # CALLBACK wiring — the actor arriving as an argument, the direction of the
    # discarded_at change, and the write surviving a broken notifier.
    describe "member removed (after_update_commit)" do
      let!(:membership) { create(:membership, user: member, workspace: workspace) }

      it "hands the notifier the actor the caller named, without reading Current" do
        membership.deactivate!(removed_by: owner)

        event = Noticed::Event.where(type: "WorkspaceMemberRemovedNotifier").last
        expect(event).to be_present
        expect(event.record).to eq(membership)
        expect(event.reload.params[:actor]).to eq(owner)
      end

      it "leaves the actor nil when the caller names none" do
        membership.deactivate!

        event = Noticed::Event.where(type: "WorkspaceMemberRemovedNotifier").last
        expect(event.reload.params[:actor]).to be_nil
      end

      it "does not reuse an earlier actor when a later removal names none" do
        membership.deactivate!(removed_by: owner)
        membership.reactivate!(granted_by: owner)
        # Past the one-minute idempotency bucket, so the second removal is a
        # new event rather than a dedup drop of the first.
        travel_to(2.minutes.from_now) { membership.deactivate! }

        event = Noticed::Event.where(type: "WorkspaceMemberRemovedNotifier").order(:created_at).last
        expect(event.reload.params[:actor]).to be_nil
      end

      # Same best-effort posture the rest of the notification wiring has: the
      # business write is not hostage to the fan-out.
      it "still removes the member when the notifier raises" do
        allow(WorkspaceMemberRemovedNotifier).to receive(:with).and_raise(StandardError, "boom")

        expect { membership.deactivate!(removed_by: owner) }.not_to raise_error
        expect(membership.reload).to be_discarded
      end
    end

    # Re-admission is an undiscard, not a create, so after_create_commit never
    # fires — a previously removed member came silently back with zero
    # notifications. Covered here rather than in the notifier spec because the
    # bug was in the callback wiring.
    describe "member re-admitted (after_update_commit)" do
      include ActiveJob::TestHelper

      let!(:membership) { create(:membership, user: member, workspace: workspace) }

      before do
        membership.deactivate!
        Noticed::Notification.delete_all
        Noticed::Event.delete_all
        ActionMailer::Base.deliveries.clear
        clear_enqueued_jobs
      end

      it "notifies the re-admitted member and the owners on Membership#reactivate!" do
        expect {
          membership.reactivate!
        }.to change { Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").count }.by(1)

        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event.record).to eq(membership)
        expect(event.notifications.map(&:recipient)).to contain_exactly(member, owner)
      end

      it "excludes the actor who performed the re-admission" do
        membership.reactivate!(granted_by: owner)
        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end

      it "notifies through Workspace#admit's undiscard branch too, minus the actor" do
        workspace.admit(member, role: Role.system_default!("member"), granted_by: owner)
        event = Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").last
        expect(event).to be_present
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end

      # WorkspaceMemberAddedNotifier's email, not WelcomeNotifier's — that one
      # is the account's day-one notice and has no email leg at all.
      it "sends the re-admitted member WorkspaceMemberAddedNotifier's email, as a fresh add would" do
        perform_enqueued_jobs(only: Noticed::EventJob) { membership.reactivate! }
        perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
        perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)

        expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq([ member.email_address ])
      end

      it "does not notify on deactivation" do
        membership.reactivate!
        Noticed::Event.delete_all
        expect {
          membership.deactivate!
        }.not_to change { Noticed::Event.where(type: "WorkspaceMemberAddedNotifier").count }
      end

      # #935: same best-effort posture as the fresh-add path above — it is the
      # same underlying callback, reached through the undiscard branch.
      it "still re-admits the member when the notifier raises" do
        allow(WorkspaceMemberAddedNotifier).to receive(:with).and_raise(StandardError, "boom")
        expect(Rails.error).to receive(:report).with(
          kind_of(StandardError),
          hash_including(handled: true, context: hash_including(action: "member_added"))
        )

        expect { membership.reactivate! }.not_to raise_error
        expect(membership.reload).not_to be_discarded
      end

      # track_creation is the only writer of grant provenance, and a
      # re-admission is an UPDATE, so re-granting a previously removed member
      # recorded who did it nowhere: `changes: {discarded_at: [...]}` and an
      # actor that, on the invitation path, is the invitee themselves.
      describe "grant provenance on the audit row" do
        def reactivation_row
          ActivityLog.where(action: "membership.updated", trackable: membership).last
        end

        before { ActivityLog.where(trackable: membership).delete_all }

        it "records the granter on the re-admission row" do
          membership.reactivate!(granted_by: owner)

          expect(reactivation_row.metadata["granted_by"]).to eq(owner.id)
        end

        it "records the granter when the re-admission comes through Workspace#admit" do
          workspace.admit(member, role: Role.system_default!("member"), granted_by: owner)

          expect(reactivation_row.metadata["granted_by"]).to eq(owner.id)
        end

        it "still records the changed columns alongside it" do
          membership.reactivate!(granted_by: owner)

          expect(reactivation_row.metadata["changes"]).to have_key("discarded_at")
        end

        it "claims no granter for a re-admission that had none" do
          membership.reactivate!

          expect(reactivation_row.metadata).not_to have_key("granted_by")
        end

        it "claims no granter for an ordinary update that is not a re-admission" do
          membership.reactivate!
          ActivityLog.where(trackable: membership).delete_all
          membership.granted_by = owner
          membership.update!(role: Role.system_default!("admin"))

          expect(reactivation_row.metadata).not_to have_key("granted_by")
        end
      end
    end

    describe "role changed (after_update_commit)" do
      let!(:membership) { create(:membership, user: member, workspace: workspace) }
      let(:admin_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }

      it "notifies the member when their role changes" do
        expect {
          membership.change_role!(admin_role)
        }.to change { Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").count }.by(1)
        event = Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end

      it "does not notify on a save that leaves the role unchanged" do
        expect {
          membership.update!(last_accessed_at: Time.current)
        }.not_to change { Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").count }
      end

      it "transfer_ownership_to! notifies the promoted member, not the demoted initiator" do
        expect {
          owner_membership.transfer_ownership_to!(membership)
        }.to change { Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").count }.by(1)
        event = Noticed::Event.where(type: "WorkspaceRoleChangedNotifier").last
        expect(event.notifications.map(&:recipient)).to eq([ member ])
      end

      # #935: same best-effort posture as the rest of the notification wiring.
      it "still changes the role when the notifier raises" do
        allow(WorkspaceRoleChangedNotifier).to receive(:with).and_raise(StandardError, "boom")
        expect(Rails.error).to receive(:report).with(
          kind_of(StandardError),
          hash_including(handled: true, context: hash_including(action: "role_changed"))
        )

        expect { membership.change_role!(admin_role) }.not_to raise_error
        expect(membership.reload.role).to eq(admin_role)
      end
    end

    # #935: the self-joiner's orientation notice is best-effort too — a
    # raising notifier must not turn the join or the re-admission into a 500.
    describe "self joined (after_create_commit)" do
      it "still creates the membership when the notifier raises" do
        allow(WorkspaceJoinedNotifier).to receive(:with).and_raise(StandardError, "boom")
        expect(Rails.error).to receive(:report).with(
          kind_of(StandardError),
          hash_including(handled: true, context: hash_including(action: "self_joined"))
        )

        membership = nil
        expect {
          membership = create(:membership, user: member, workspace: workspace, self_join: true)
        }.not_to raise_error
        expect(membership.reload).to be_persisted
      end
    end

    describe "self rejoined (after_update_commit)" do
      let!(:membership) { create(:membership, user: member, workspace: workspace) }

      before { membership.deactivate! }

      it "still re-admits the member when the notifier raises" do
        allow(WorkspaceJoinedNotifier).to receive(:with).and_raise(StandardError, "boom")
        expect(Rails.error).to receive(:report).with(
          kind_of(StandardError),
          hash_including(handled: true, context: hash_including(action: "self_joined"))
        )

        expect { membership.reactivate!(self_join: true) }.not_to raise_error
        expect(membership.reload).not_to be_discarded
      end
    end
  end
end
