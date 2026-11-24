require "rails_helper"

# D13 requires BOTH callers to render the over-limit signal. The model
# reporting it is not the guarantee — a caller that ignores it truncates the
# sender's list silently, which is the failure this pins.
RSpec.describe "Invite address cap at the surfaces", type: :request do
  def cap
    Invitation::MAX_EMAILS_PER_SUBMISSION
  end

  def over_limit_list
    Array.new(cap + 3) { |i| "invitee#{i}@example.test" }.join(", ")
  end

  describe "workspace invitations" do
    def sign_in_as_workspace_owner
      user = create(:user)
      workspace = create(:workspace)
      create(:membership, user: user, workspace: workspace,
                          role: Role.system_default!("owner"))
      sign_in(user)
      workspace
    end

    it "invites up to the cap and says the rest were not sent" do
      workspace = sign_in_as_workspace_owner
      post workspace_invitations_path(workspace),
           params: { invitation: { emails: over_limit_list,
                                   role_id: Role.system_default!("member").id } }

      expect(workspace.invitations.count).to eq(cap)
      expect(flash[:notice]).to include(
        I18n.t("workspaces.invitations.create.capped", cap: cap)
      )
    end

    it "says nothing about a cap for a submission within it" do
      workspace = sign_in_as_workspace_owner
      post workspace_invitations_path(workspace),
           params: { invitation: { emails: "one@example.test",
                                   role_id: Role.system_default!("member").id } }

      expect(flash[:notice]).not_to include(
        I18n.t("workspaces.invitations.create.capped", cap: cap)
      )
    end
  end
end
