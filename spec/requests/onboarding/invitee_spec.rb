require "rails_helper"

# Under :none an invitee is not a first-run user — the wizard exists for the
# self-signup who has nowhere to go. Left unstamped, an invited Member was
# funnelled into the invite step, refused by InvitationPolicy, redirected to
# the workspace, and funnelled again: "redirected you too many times".
RSpec.describe "Onboarding · invitees", type: :request do
  before { allow(TenancyConfig).to receive(:onboarding).and_return(:none) }

  def owned_workspace
    owner = create(:user, :with_zero_workspaces, onboarded_at: Time.current)
    workspace = create(:workspace)
    create(:membership, :owner, user: owner, workspace: workspace)
    [ workspace, owner ]
  end

  def accept_as(role, workspace:, owner:)
    invitee = create(:user, :with_zero_workspaces)
    create(:invitation, invitable: workspace, role: role, invited_by: owner, email: invitee.email_address)
      .accept!(invitee)
    invitee
  end

  it "lands an invited Member on their workspace, never in the wizard" do
    workspace, owner = owned_workspace
    member_role = Role.system_default!("member")
    invitee = accept_as(member_role, workspace: workspace, owner: owner)
    sign_in(invitee)

    get new_session_path
    expect(response).not_to redirect_to(onboarding_path)
    get workspace_path(workspace)
    expect(response).to have_http_status(:ok)
    expect(invitee.reload).to be_onboarded
  end

  # Fork (MClassrooms): the wizard is the single workspace step
  # (config/routes.rb draws onboarding/workspace only), so upstream's two
  # examples probing the invite step (new_onboarding_team_path) have no
  # surface here; Workspace#admit stamping onboarded_at is what the example
  # above pins.
end
