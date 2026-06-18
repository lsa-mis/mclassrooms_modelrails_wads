require "rails_helper"

# Verifies the settings layout (app/views/layouts/settings.html.erb) subscribes
# the authenticated user's page to the current workspace's Turbo stream when in
# org context. This is the SUBSCRIBER half of the Membership broadcast contract:
# Membership includes Broadcastable and broadcasts refresh to its workspace on
# create + update (covered by spec/models/broadcasts_spec.rb). Without the
# layout subscription, those broadcasts have no listener — and the Phase 2
# demotion-while-viewing flow (Task 15) cannot re-render the demoted user's
# open settings tab.
RSpec.describe "Settings layout workspace stream subscription", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  context "on an org-context settings page" do
    let(:workspace) { create(:workspace) }
    let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

    it "subscribes the page to the workspace stream so membership broadcasts re-render the layout" do
      # /workspaces/:slug/edit now renders the Profile destination directly
      # (no redirect) after the settings hub route consolidation.
      get edit_workspace_path(workspace), headers: { "HTTP_ACCEPT" => "text/html" }

      # Settings layout uses `turbo_stream_from` which renders a
      # <turbo-cable-stream-source> custom element with a signed channel name.
      # Assert both the element and the signed stream name match what
      # `turbo_stream_from Current.workspace` would produce.
      expect(response.body).to include("turbo-cable-stream-source")

      expected_signed_name = Turbo::StreamsChannel.signed_stream_name(workspace)
      expect(response.body).to include(expected_signed_name)
    end
  end

  context "on a personal-context settings page" do
    it "does NOT subscribe to a workspace stream (personal workspace broadcasts are self-broadcasts)" do
      get edit_settings_profile_path

      personal = user.personal_workspace
      personal_signed_name = Turbo::StreamsChannel.signed_stream_name(personal)
      expect(response.body).not_to include(personal_signed_name)
    end
  end
end
