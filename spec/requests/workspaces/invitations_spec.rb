require "rails_helper"

RSpec.describe "Workspace Invitations", type: :request do
  def signed_in_owner
    membership = create(:membership, :owner)
    Current.workspace = membership.workspace
    sign_in(membership.user)
    membership
  end

  context "authenticated" do
    describe "GET /workspaces/:workspace_slug/invitations/new" do
      it "renders the invitation form" do
        membership = signed_in_owner
        workspace = membership.workspace
        get new_workspace_invitation_path(workspace)
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /workspaces/:workspace_slug/invitations" do
      it "creates an invitation and sends email" do
        membership = signed_in_owner
        workspace = membership.workspace
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { emails: "test@example.com", role_id: membership.role.id }
          }
        }.to change(Invitation, :count).by(1)
          .and have_enqueued_mail(InvitationMailer, :invite)

        # sent:/skipped:, not count: the cap on addresses is never silent.
        expect(flash[:notice]).to eq(I18n.t("workspaces.invitations.create.sent", sent: 1, skipped: 0))
      end

      it "creates batch invitations" do
        membership = signed_in_owner
        workspace = membership.workspace
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { emails: "a@example.com\nb@example.com", role_id: membership.role.id }
          }
        }.to change(Invitation, :count).by(2)
      end

      it "creates a magic link invitation" do
        membership = signed_in_owner
        workspace = membership.workspace
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { magic_link: "1", role_id: membership.role.id }
          }
        }.to change(Invitation, :count).by(1)

        expect(workspace.invitations.find_by(email: nil)).to be_magic_link.and be_acceptable
        expect(response).to redirect_to(workspace_members_path(workspace))
        expect(flash[:notice]).to eq(I18n.t("workspaces.invitations.create.magic_link_created"))
      end

      it "skips existing members" do
        membership = signed_in_owner
        workspace = membership.workspace
        existing = create(:user, email_address: "existing@example.com")
        create(:membership, user: existing, workspace: workspace)

        post workspace_invitations_path(workspace), params: {
          invitation: { emails: "existing@example.com", role_id: membership.role.id }
        }
        expect(Invitation.where(email: "existing@example.com")).to be_empty
      end

      it "skips duplicate pending invitations" do
        membership = signed_in_owner
        workspace = membership.workspace
        user = membership.user
        create(:invitation, invitable: workspace, email: "dup@example.com", invited_by: user)

        post workspace_invitations_path(workspace), params: {
          invitation: { emails: "dup@example.com", role_id: membership.role.id }
        }
        expect(Invitation.where(email: "dup@example.com").count).to eq(1)
      end
    end

    describe "DELETE /workspaces/:workspace_slug/invitations/:id" do
      it "revokes the invitation" do
        membership = signed_in_owner
        workspace = membership.workspace
        invitation = create(:invitation, invitable: workspace, invited_by: membership.user)
        delete workspace_invitation_path(workspace, invitation)
        expect(invitation.reload).to be_revoked
      end
    end

    # Resending is the create of a resend nested under the invitation (#1007).
    describe "POST /workspaces/:workspace_slug/invitations/:id/resend" do
      it "resends the invitation email" do
        membership = signed_in_owner
        workspace = membership.workspace
        invitation = create(:invitation, invitable: workspace, invited_by: membership.user)
        expect {
          post workspace_invitation_resend_path(workspace, invitation)
        }.to have_enqueued_mail(InvitationMailer, :invite)
      end

      it "dispatches a WorkspaceInvitationResentNotifier to the inviter on first resend" do
        membership = signed_in_owner
        workspace = membership.workspace
        user = membership.user
        invitation = create(:invitation, invitable: workspace, invited_by: membership.user)
        expect {
          post workspace_invitation_resend_path(workspace, invitation)
        }.to change { user.notifications.where(type: "WorkspaceInvitationResentNotifier::Notification").count }.by(1)
      end

      it "says it was rate limited once the limit is exceeded, and sends nothing" do
        membership = signed_in_owner
        workspace = membership.workspace
        invitation = create(:invitation, invitable: workspace, invited_by: membership.user)
        allow(Rails.cache).to receive(:increment).and_return(11)

        expect { post workspace_invitation_resend_path(workspace, invitation) }.not_to have_enqueued_mail
        expect(response).to redirect_to(workspace_members_path(workspace))
        expect(flash[:alert]).to eq(I18n.t("workspaces.invitations.resends.create.rate_limited"))
      end

      it "shows the 'resent' flash on first resend" do
        membership = signed_in_owner
        workspace = membership.workspace
        invitation = create(:invitation, invitable: workspace, invited_by: membership.user)
        post workspace_invitation_resend_path(workspace, invitation)
        expect(flash[:notice]).to eq(I18n.t("workspaces.invitations.resends.create.resent"))
      end

      it "shows the 'recently_sent' flash on a second rapid resend (sentinel :deduplicated branch)" do
        membership = signed_in_owner
        workspace = membership.workspace
        invitation = create(:invitation, invitable: workspace, invited_by: membership.user)
        # Two resends inside the 1-minute idempotency bucket. The first
        # creates the notification (sentinel :delivered, "resent" flash);
        # the second collides on the unique idempotency_key and returns
        # :deduplicated, which the controller branches into "recently_sent".
        # We DO NOT stub the notifier — we exercise the real DB constraint
        # so this regression-protects the actual production branch.
        freeze_time do
          post workspace_invitation_resend_path(workspace, invitation)
          first_flash = flash[:notice]
          post workspace_invitation_resend_path(workspace, invitation)
          second_flash = flash[:notice]

          expect(first_flash).to eq(I18n.t("workspaces.invitations.resends.create.resent"))
          expect(second_flash).to eq(I18n.t("workspaces.invitations.resends.create.recently_sent"))

          # Make the dedup mechanism explicit: the second dispatch's
          # populate_idempotency_key callback computed the same
          # `<NotifierClass>_<invitation.id>_<minute_bucket>` seed as the first
          # — that's what the partial unique index on noticed_events
          # (idempotency_key) catches, raising RecordNotUnique inside
          # ApplicationNotifier#deliver, which the rescue clause turns into
          # the :deduplicated sentinel. The test exercises this end-to-end
          # via the real DB constraint (no stubs), so we should observe
          # exactly one event row for this notifier+invitation tuple inside
          # the frozen minute.
          events = Noticed::Event.where(type: WorkspaceInvitationResentNotifier.name).order(:created_at)
          expect(events.count).to eq(1)
          expect(events.first.idempotency_key).to be_present
          expected_key = "#{WorkspaceInvitationResentNotifier.name}_#{invitation.id}_#{Time.current.to_i / 60}"
          expect(events.first.idempotency_key).to eq(expected_key)
        end
      end

      it "still enqueues the invitee email even when the inviter notification is deduplicated" do
        membership = signed_in_owner
        workspace = membership.workspace
        invitation = create(:invitation, invitable: workspace, invited_by: membership.user)
        # The mailer call is intentionally unconditional — the dedup applies
        # only to the in-app confirmation surface for the inviter, not to
        # the invitee email path. Verifies we didn't accidentally short-circuit
        # both on the dedup branch.
        freeze_time do
          post workspace_invitation_resend_path(workspace, invitation)
          expect {
            post workspace_invitation_resend_path(workspace, invitation)
          }.to have_enqueued_mail(InvitationMailer, :invite)
        end
      end
    end

    describe "POST /workspaces/:workspace_slug/invitations with empty emails" do
      it "creates no invitations for empty string" do
        membership = signed_in_owner
        workspace = membership.workspace
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { emails: "", role_id: membership.role.id }
          }
        }.not_to change(Invitation, :count)
      end
    end

    describe "POST /workspaces/:workspace_slug/invitations with comma-separated emails" do
      it "creates invitations for comma-separated emails" do
        membership = signed_in_owner
        workspace = membership.workspace
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { emails: "comma1@example.com, comma2@example.com", role_id: membership.role.id }
          }
        }.to change(Invitation, :count).by(2)
      end
    end

    describe "authorization" do
      it "denies member from creating invitations" do
        membership = signed_in_owner
        workspace = membership.workspace
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
        membership = signed_in_owner
        workspace = membership.workspace
        other_workspace = create(:workspace)
        foreign_role = Role.create!(name: "Foreign", slug: "foreign", workspace: other_workspace)
        post workspace_invitations_path(workspace), params: {
          invitation: { emails: "test@example.com", role_id: foreign_role.id }
        }
        expect(response).to have_http_status(:not_found).or have_http_status(:redirect)
      end
    end

    # SEC-1: an Admin must not be able to invite (or magic-link) an Owner.
    describe "privilege escalation via invitation role" do
      def signed_in_admin
        membership = signed_in_owner
        admin = create(:membership, :admin, workspace: membership.workspace)
        sign_in(admin.user)
        membership
      end

      it "refuses an email invitation carrying the owner role" do
        membership = signed_in_admin
        workspace = membership.workspace
        owner_role = Role.system_default!("owner")
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { emails: "escalate@example.com", role_id: owner_role.id }
          }
        }.not_to change(Invitation, :count)
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to be_present
      end

      it "refuses a magic-link invitation carrying the owner role" do
        membership = signed_in_admin
        workspace = membership.workspace
        owner_role = Role.system_default!("owner")
        expect {
          post workspace_invitations_path(workspace), params: {
            invitation: { magic_link: "1", role_id: owner_role.id }
          }
        }.not_to change(Invitation, :count)
        expect(response).to have_http_status(:redirect)
      end

      it "does not offer the Owner option in an admin's invitation form" do
        membership = signed_in_admin
        workspace = membership.workspace
        get new_workspace_invitation_path(workspace)
        select = Nokogiri::HTML(response.body).at_css("select[name='invitation[role_id]']")
        expect(select.to_s).not_to include("Owner")
      end
    end
  end
end
