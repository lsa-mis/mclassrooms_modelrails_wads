require "rails_helper"

RSpec.describe "Workspace Invitations", type: :request do
  describe "unauthenticated access" do
    it "redirects GET /workspaces/:slug/invitations to sign in" do
      get workspace_invitations_path(workspace_slug: "any-slug")
      expect(response).to redirect_to(new_session_path)
    end
  end

  context "authenticated" do
    let(:workspace) { create(:workspace) }
    let(:user) { create(:user) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    before do
      Current.workspace = workspace
      sign_in(user)
    end

    describe "GET /workspaces/:workspace_slug/invitations" do
      it "lists invitations" do
        create(:invitation, invitable: workspace, invited_by: user)
        get workspace_invitations_path(workspace)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /workspaces/:workspace_slug/invitations/new" do
      it "renders the invitation form" do
        get new_workspace_invitation_path(workspace)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /workspaces/:workspace_slug/invitations" do
      it "creates an invitation and sends email" do
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { emails: "test@example.com", role_id: membership.role.id }
          }
        }.to change(Invitation, :count).by(1)
          .and have_enqueued_mail(InvitationMailer, :invite)
      end

      it "creates batch invitations" do
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { emails: "a@example.com\nb@example.com", role_id: membership.role.id }
          }
        }.to change(Invitation, :count).by(2)
      end

      it "creates a magic link invitation" do
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { magic_link: "1", role_id: membership.role.id }
          }
        }.to change(Invitation, :count).by(1)

        expect(workspace.invitations.find_by(email: nil)).to be_magic_link
      end

      it "skips existing members" do
        existing = create(:user, email_address: "existing@example.com")
        create(:membership, user: existing, workspace: workspace)

        post workspace_invitations_path(workspace), params: {
          invitation: { emails: "existing@example.com", role_id: membership.role.id }
        }
        expect(Invitation.where(email: "existing@example.com")).to be_empty
      end

      it "skips duplicate pending invitations" do
        create(:invitation, invitable: workspace, email: "dup@example.com", invited_by: user)

        post workspace_invitations_path(workspace), params: {
          invitation: { emails: "dup@example.com", role_id: membership.role.id }
        }
        expect(Invitation.where(email: "dup@example.com").count).to eq(1)
      end
    end

    describe "DELETE /workspaces/:workspace_slug/invitations/:id" do
      let!(:invitation) { create(:invitation, invitable: workspace, invited_by: user) }

      it "revokes the invitation" do
        delete workspace_invitation_path(workspace, invitation)
        expect(invitation.reload).to be_revoked
      end
    end

    describe "POST /workspaces/:workspace_slug/invitations/:id/resend" do
      let!(:invitation) { create(:invitation, invitable: workspace, invited_by: user) }

      it "resends the invitation" do
        expect {
          post resend_workspace_invitation_path(workspace, invitation)
        }.to have_enqueued_mail(InvitationMailer, :invite)
      end
    end

    describe "POST /workspaces/:workspace_slug/invitations with empty emails" do
      it "creates no invitations for empty string" do
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { emails: "", role_id: membership.role.id }
          }
        }.not_to change(Invitation, :count)
      end
    end

    describe "POST /workspaces/:workspace_slug/invitations with comma-separated emails" do
      it "creates invitations for comma-separated emails" do
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { emails: "comma1@example.com, comma2@example.com", role_id: membership.role.id }
          }
        }.to change(Invitation, :count).by(2)
      end
    end

    describe "authorization" do
      it "denies member from creating invitations" do
        member = create(:user)
        create(:membership, user: member, workspace: workspace)
        sign_in(member)

        post workspace_invitations_path(workspace), params: {
          invitation: { emails: "test@example.com", role_id: membership.role.id }
        }
        # Pundit raises, rescue_from redirects
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "role injection protection" do
      it "rejects role from another workspace" do
        other_workspace = create(:workspace)
        foreign_role = Role.create!(name: "Foreign", slug: "foreign", workspace: other_workspace)
        post workspace_invitations_path(workspace), params: {
          invitation: { emails: "test@example.com", role_id: foreign_role.id }
        }
        expect(response).to have_http_status(:not_found).or have_http_status(:redirect)
      end
    end
  end
end
