require "rails_helper"

RSpec.describe "Invitation blocks", type: :request do
  let(:invitation) { create(:invitation) }
  let(:token) { invitation.generate_token_for(:block_confirmation) }

  it "has no bearer block route any more (#951)" do
    post "/invitations/#{invitation.token}/block"
    expect(response).to have_http_status(:not_found)
  end

  describe "GET /invitation_block?token=" do
    it "renders the confirmation and blocks nothing" do
      get invitation_block_path(token: token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("invitation_blocks.show.title", inviter: invitation.invited_by.email_address))
      expect(invitation.reload).to be_pending
      expect(InvitationBlock.exists?(inviter_id: invitation.invited_by_id, email: invitation.email)).to be(false)
    end

    it "shows the shared invalid message for a bad token" do
      get invitation_block_path(token: "nope")
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_blocks.invalid"))
    end

    it "refuses a magic-link invitation the same way" do
      bearer = create(:invitation, :magic_link)
      get invitation_block_path(token: bearer.generate_token_for(:block_confirmation))
      expect(flash[:alert]).to eq(I18n.t("invitation_blocks.invalid"))
    end

    it "refuses an expired invitation, in step with the decline flow" do
      expired = create(:invitation, :expired)
      get invitation_block_path(token: expired.generate_token_for(:block_confirmation))
      expect(flash[:alert]).to eq(I18n.t("invitation_blocks.invalid"))
    end

    it "shows the shared invalid message once the invitation was accepted (the token died with the status)" do
      spent = token
      invitation.accept!(create(:user))
      get invitation_block_path(token: spent)
      expect(flash[:alert]).to eq(I18n.t("invitation_blocks.invalid"))
    end
  end

  describe "POST /invitation_block" do
    it "declines, blocks, and states the outcome in the document" do
      post invitation_block_path, params: { token: token }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("invitation_blocks.create.blocked_title", inviter: invitation.invited_by.email_address))
      expect(invitation.reload).to be_declined
      expect(invitation).to be_suppressed
      expect(InvitationBlock.exists?(inviter_id: invitation.invited_by_id, email: invitation.email)).to be(true)
    end

    it "refuses a spent token on a repeat, without a second block row" do
      spent = token
      post invitation_block_path, params: { token: spent }
      post invitation_block_path, params: { token: spent }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_blocks.invalid"))
      expect(InvitationBlock.where(inviter_id: invitation.invited_by_id, email: invitation.email).count).to eq(1)
    end

    it "keeps the block on the in-flight race (filter passes, decline! loses)" do
      # Two-instance shape at the HTTP boundary: accept between GET and POST is
      # covered above; here the filter sees pending but decline! meets accepted.
      # allow_any_instance_of is a named smell, justified here: no fixture
      # ordering at the HTTP boundary can produce this interleaving — the
      # model-level race is pinned with real rows elsewhere (T9).
      allow_any_instance_of(Invitation).to receive(:decline!)
        .and_raise(ActiveRecord::RecordInvalid.new(invitation))
      post invitation_block_path, params: { token: token }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("invitation_blocks.already_processed.title"))
      expect(InvitationBlock.exists?(inviter_id: invitation.invited_by_id, email: invitation.email)).to be(true)
    end

    it "refuses a magic-link invitation on the mutating verb too: nothing to block for" do
      bearer = create(:invitation, :magic_link)
      post invitation_block_path, params: { token: bearer.generate_token_for(:block_confirmation) }
      expect(flash[:alert]).to eq(I18n.t("invitation_blocks.invalid"))
      expect(InvitationBlock.count).to eq(0)
      expect(bearer.reload).to be_pending
    end

    it "rate limits via the cache counter (T18)" do
      allow(Rails.cache).to receive(:increment).and_return(11)
      post invitation_block_path, params: { token: token }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("invitation_blocks.create.rate_limited"))
    end
  end

  describe "the inviter's-eye journey (T22, invariant I3)" do
    include ActiveJob::TestHelper

    it "keeps the blocked invitation indistinguishable in the inviter's surfaces" do
      workspace = create(:workspace)
      inviter = create(:user)
      create(:membership, :owner, user: inviter, workspace: workspace)
      role = Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }

      Invitation.bulk_invite!(workspace: workspace, emails: [ "target@example.com" ],
                              role: role, invited_by: inviter)
      invitation = Invitation.find_by(email: "target@example.com")

      post invitation_block_path, params: { token: invitation.generate_token_for(:block_confirmation) }
      expect(Invitation.find(invitation.id)).to be_declined

      # A declined invitation leaves the members index anyway; the oracle test
      # is the PENDING ghost from a fresh invite:
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
        Invitation.bulk_invite!(workspace: workspace, emails: [ "target@example.com" ],
                                role: role, invited_by: inviter)
      end
      ghost = Invitation.pending.find_by(email: "target@example.com")
      expect(ghost).to be_suppressed
      expect(Invitation.for_members_index(role: nil, status: nil)).to include(ghost)
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(ActivityLog.visible.for_workspace(workspace).where(trackable: ghost)
               .where.not(action: "invitation.created").count).to eq(0)
    end
  end
end
