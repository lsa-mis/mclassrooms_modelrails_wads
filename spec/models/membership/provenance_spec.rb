require "rails_helper"

# Membership::Provenance's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe Membership, type: :model do
  # `granted_by` and `self_join` are mutually exclusive: nobody granted a
  # self-join. Before the guard, passing both silently let self_join win the
  # actor selection while granted_by still landed in the membership.created
  # audit row — a row naming a granter for something the same row records as
  # ungranted. Both entry points refuse it.
  describe "exclusive grant provenance" do
    let(:workspace) { create(:workspace, personal: false) }
    let(:granter) { create(:user) }
    let(:member_role) do
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
    end

    it "refuses a Workspace#admit claiming both a granter and a self-join" do
      expect {
        workspace.admit(create(:user), role: member_role, granted_by: granter, self_join: true)
      }.to raise_error(ArgumentError, /mutually exclusive/)
    end

    it "refuses the same combination on #reactivate!" do
      membership = create(:membership, workspace: workspace, role: member_role)
      membership.discard!

      expect {
        membership.reactivate!(granted_by: granter, self_join: true)
      }.to raise_error(ArgumentError, /mutually exclusive/)
    end

    it "creates nothing when it refuses" do
      expect {
        expect {
          workspace.admit(create(:user), role: member_role, granted_by: granter, self_join: true)
        }.to raise_error(ArgumentError)
      }.not_to change(workspace.memberships, :count)
    end

    it "still accepts either one on its own" do
      expect { workspace.admit(create(:user), role: member_role, granted_by: granter) }.not_to raise_error
      expect { workspace.admit(create(:user), role: member_role, self_join: true) }.not_to raise_error
    end

    # The two entry-point guards only see callers that go through them.
    # User#join_shared_workspace creates a membership directly, and the
    # actor-stance fence is satisfied by EITHER marker — so a site naming both
    # reads as "declared" and reaches the row. The rule belongs on the model,
    # where no construction path can route around it.
    context "as a model invariant" do
      it "refuses both markers on a direct create!, which no entry-point guard sees" do
        expect {
          workspace.memberships.create!(
            user: create(:user), role: member_role, granted_by: granter, self_join: true
          )
        }.to raise_error(ActiveRecord::RecordInvalid, /mutually exclusive/)
      end

      it "creates nothing when the direct create! is refused" do
        expect {
          expect {
            workspace.memberships.create!(
              user: create(:user), role: member_role, granted_by: granter, self_join: true
            )
          }.to raise_error(ActiveRecord::RecordInvalid)
        }.not_to change(workspace.memberships, :count)
      end

      it "refuses a self_join grade outside the declared set" do
        expect {
          workspace.memberships.create!(user: create(:user), role: member_role, self_join: :onboard)
        }.to raise_error(ActiveRecord::RecordInvalid, /self_join/)
      end

      it "accepts every declared grade" do
        [ nil, false, true, :onboarding ].each do |grade|
          membership = build(:membership, workspace: workspace, role: member_role, user: create(:user))
          membership.self_join = grade

          expect(membership).to be_valid, "grade #{grade.inspect} was rejected"
        end
      end
    end

    # chosen_self_join? gates the orientation notice, and it runs in an
    # after_create_commit — i.e. on paths that skipped validation. Asking
    # "is it the chosen grade" (inclusion) rather than "is it anything but
    # :onboarding" (exclusion) means a grade nobody taught it about stays
    # silent instead of mailing someone.
    it "does not treat an unrecognised grade as a chosen self-join" do
      create(:membership, :owner, workspace: workspace)
      joiner = create(:user)
      membership = workspace.memberships.build(user: joiner, role: member_role)
      membership.self_join = :onboard
      membership.save!(validate: false)

      expect(
        Noticed::Notification.where(recipient: joiner,
                                    type: "WorkspaceJoinedNotifier::Notification").count
      ).to eq 0
    end
  end
end
