# frozen_string_literal: true

require "rails_helper"

# The activity feed names the member a membership row is ABOUT, which means
# every membership row traverses `trackable.user`. Bullet raises on an N+1 in
# test, so this is the guard on `ActivityLog.for_feed`'s per-slice preload —
# the view spec renders one row at a time and can never see it.
RSpec.describe "Workspace activity feed", type: :request do
  let(:workspace) { create(:workspace) }
  let(:owner) { create(:user) }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    # Three membership rows, because Bullet only reports a lazy load that
    # happens on 2+ members of one collection.
    create(:membership, user: create(:user, first_name: "Bea"), workspace: workspace)
    create(:membership, user: create(:user, first_name: "Cal"), workspace: workspace)
    create(:membership, user: create(:user, first_name: "Dee"), workspace: workspace)
    sign_in(owner)
  end

  it "renders the feed without lazily loading each row's member" do
    get workspace_path(workspace)

    expect(response).to have_http_status(:ok)
  end

  # `membership.created` is subject-only ("Bea joined the workspace"), so the
  # object-naming copy is exercised through removals.
  it "names the member each removal row is about" do
    workspace.memberships.kept.where.not(user: owner).find_each { |m| m.deactivate!(removed_by: owner) }

    get workspace_path(workspace)
    page = Capybara.string(response.body)

    expect(page).to have_text("deactivated Bea", normalize_ws: true)
    expect(page).to have_text("deactivated Dee", normalize_ws: true)
  end

  # A feed whose rows are not memberships must not pay for the membership hop,
  # and must not trip Bullet's unused-eager-loading check either.
  it "renders a feed of non-membership rows cleanly" do
    workspace.memberships.where.not(user: owner).find_each { |m| m.deactivate!(removed_by: owner) }
    ActivityLog.where(trackable_type: "Membership").delete_all
    3.times { |i| create(:invitation, invitable: workspace, email: "invitee#{i}@example.test") }

    get workspace_path(workspace)

    expect(response).to have_http_status(:ok)
  end
end
