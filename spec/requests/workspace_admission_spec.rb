require "rails_helper"

# Exercises ApplicationController's app-wide Workspace::NotAdmittableError
# rescue (not_admittable). #admit is stubbed to raise so the error fires past
# a site-guard that otherwise passes on an active/open-join workspace — the
# TOCTOU race where a workspace goes non-admittable under admit's lock. Once
# Task 5's widened guards drop the normal stale cases earlier, this race is
# the only path that reaches the rescue, so it must be proven with a stub.
RSpec.describe "Workspace admission (not_admittable rescue)", type: :request do
  let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
  let(:owner) { create(:user) }
  let(:newcomer) { create(:user) }
  let!(:owner_role) {
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_settings: true }
    }
  }
  let!(:member_role) {
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
      r.name = "Member"
      r.permissions = {}
    }
  }
  let(:link) { create(:workspace_join_link, workspace: workspace, created_by: owner) }

  before do
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    workspace.memberships.create!(user: owner, role: owner_role)
    sign_in(newcomer)
    allow_any_instance_of(Workspace).to receive(:admit).and_raise(Workspace::NotAdmittableError)
  end

  it "redirects to root_path with the generic invalid_or_revoked flash, never disclosing lifecycle state" do
    post workspace_join_path(workspace, token: link.token)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
    expect(flash[:alert]).not_to match(/archived|deleted|locked|suspended/i)
  end
end

# Task 5: widens the open-join-link and invitation-acceptance guards from
# suspended? to admittable?, so archived AND deleted workspaces reject new
# admission the same way suspended ones already did. Mirrors the open-link
# setup from spec/requests/workspaces/joins_spec.rb and the invitation setup
# from spec/requests/invitation_accepts_spec.rb.
RSpec.describe "Admission into non-active workspaces", type: :request do
  let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
  let(:owner) { create(:user) }
  let(:newcomer) { create(:user) }
  let!(:owner_role) {
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_settings: true }
    }
  }
  let!(:member_role) {
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
      r.name = "Member"
      r.permissions = {}
    }
  }
  let(:link) { create(:workspace_join_link, workspace: workspace, created_by: owner) }

  before do
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    workspace.memberships.create!(user: owner, role: owner_role)
  end

  %i[archive discard].each do |lifecycle_action|
    lifecycle_name = lifecycle_action == :archive ? "archived" : "deleted"

    context "workspace is #{lifecycle_name}" do
      before { workspace.public_send("#{lifecycle_action}!") }

      it "rejects an open-join-link GET with the generic invalid-or-revoked message, no disclosure" do
        sign_in(newcomer)
        get workspace_join_path(workspace, token: link.token)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
        expect(flash[:alert]).not_to match(/archived|deleted|locked|suspended/i)
      end

      it "rejects an open-join-link POST — no membership created" do
        sign_in(newcomer)

        expect {
          post workspace_join_path(workspace, token: link.token)
        }.not_to change(Membership, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("workspaces.joins.invalid_or_revoked"))
        expect(flash[:alert]).not_to match(/archived|deleted|locked|suspended/i)
      end

      it "rejects a pending workspace invitation acceptance — no membership created" do
        invitee = create(:user)
        invitation = create(:invitation, invitable: workspace, email: invitee.email_address)
        sign_in(invitee)

        expect {
          post accept_invitation_path(token: invitation.token)
        }.not_to change(Membership, :count)

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq(I18n.t("invitation_accepts.create.acceptance_failed"))
        expect(flash[:alert]).not_to match(/archived|deleted|locked|suspended/i)
      end
    end
  end
end
