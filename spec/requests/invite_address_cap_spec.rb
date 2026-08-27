require "rails_helper"

# D13 requires BOTH callers to render the over-limit signal. The model
# reporting it is not the guarantee — a caller that ignores it truncates the
# sender's list silently, which is the failure this pins.
RSpec.describe "Invite address cap at the surfaces", type: :request do
  let(:cap) { Invitation::MAX_EMAILS_PER_SUBMISSION }
  let(:user) { create(:user) }
  let(:over_limit_list) { Array.new(cap + 3) { |i| "invitee#{i}@example.test" }.join(", ") }

  describe "workspace invitations" do
    let(:workspace) { create(:workspace) }
    let!(:membership) do
      create(:membership, user: user, workspace: workspace,
                          role: Role.system_default!("owner"))
    end

    before { sign_in(user) }

    it "invites up to the cap and says the rest were not sent" do
      post workspace_invitations_path(workspace),
           params: { invitation: { emails: over_limit_list,
                                   role_id: Role.system_default!("member").id } }

      expect(workspace.invitations.count).to eq(cap)
      expect(flash[:notice]).to include(
        I18n.t("workspaces.invitations.create.capped", cap: cap)
      )
    end

    it "says nothing about a cap for a submission within it" do
      post workspace_invitations_path(workspace),
           params: { invitation: { emails: "one@example.test",
                                   role_id: Role.system_default!("member").id } }

      expect(flash[:notice]).not_to include(
        I18n.t("workspaces.invitations.create.capped", cap: cap)
      )
    end
  end

  describe "onboarding team step" do
    # The step guard derives the current step from data, so the user has to
    # genuinely be AT the team step: a workspace they own, with a project.
    let(:onboarding_user) { create(:user, :with_zero_workspaces) }
    let(:onboarding_workspace) { create(:workspace) }
    let!(:onboarding_project) { create(:project, workspace: onboarding_workspace) }

    before do
      allow(TenancyConfig).to receive(:onboarding).and_return(:none)
      onboarding_workspace.memberships.create!(
        user: onboarding_user, role: Role.system_default!("owner")
      )
      sign_in(onboarding_user)
    end

    it "refuses the submission and explains, rather than quietly dropping teammates" do
      expect {
        post onboarding_team_path,
             params: { invitation: { emails: over_limit_list,
                                     role_id: Role.system_default!("member").id } }
      }.not_to change(Invitation, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq(I18n.t("onboarding.teams.create.capped", cap: cap))
    end
  end
end
