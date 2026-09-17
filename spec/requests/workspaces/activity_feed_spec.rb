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

  # The onboarding membership is created in User#after_create, where
  # Current.user cannot exist yet (it delegates to a session that starts after
  # the signup transaction commits). Trackable therefore writes actor: nil and
  # the feed read "System joined the workspace". The row still knows who
  # joined — it IS that person's membership — so the subject comes from there.
  # Both onboarding postures create the membership inside that same callback.
  describe "a freshly registered user's first feed row" do
    before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

    def register!(email)
      token = MagicLinkToken.create_for_email(email)
      post magic_link_callback_path(token: token),
           params: { user: { first_name: "Nell", last_name: "Ramirez" } }
    end

    it "names the user, not System, on their personal workspace (:personal)" do
      register!("nell-personal@example.test")
      user = User.find_by!(email_address: "nell-personal@example.test")

      get workspace_path(user.workspaces.kept.sole)
      page = Capybara.string(response.body)

      expect(page).to have_text("Nell Ramirez #{I18n.t("activity.actions.membership.created")}", normalize_ws: true)
      expect(page).to have_no_text("System joined the workspace", normalize_ws: true)
    end

    it "names the user, not System, on the shared workspace (:shared)" do
      shared = create(:workspace, name: "Everyone")
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
      allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(shared.slug)

      register!("nell-shared@example.test")

      get workspace_path(shared)
      page = Capybara.string(response.body)

      expect(page).to have_text("Nell Ramirez #{I18n.t("activity.actions.membership.created")}", normalize_ws: true)
      expect(page).to have_no_text("System joined the workspace", normalize_ws: true)
    end
  end
end
