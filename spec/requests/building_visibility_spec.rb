require "rails_helper"

# MiClassrooms Phase 5 Task 5 (Brief §14.1): building hide/unhide — admin-only
# both ways (BuildingPolicy#hide?/#unhide? are both `grant.admin?`, unlike
# Room's one-way editor posture). Mirrors spec/requests/buildings_spec.rb's
# tenancy setup (shared-posture stub + workspace-scoped fixtures + sign_in)
# and reuses the "an admin-only action" shared example for the denial case.
RSpec.describe "Building visibility (hide/unhide)", type: :request do
  let(:workspace) { create(:workspace, slug: "building-visibility-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  let(:building) { create(:building, workspace: workspace) }
  let!(:classroom) { create(:room, building: building, workspace: workspace) }

  describe "POST /buildings/:id/hide as an admin" do
    let(:admin) { membership_with("admin") }

    before { sign_in(admin) }

    it "hides the building, stays on the building page, and audits the change" do
      expect {
        post hide_building_path(building)
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(building_path(building))
      expect(flash[:notice]).to eq(I18n.t("buildings.hide.success"))

      building.reload
      expect(building).to be_hidden
      expect(building.hidden_by).to eq(admin)

      log = ActivityLog.last
      expect(log.action).to eq("building.hidden")
      expect(log.before_after["before"]).to eq("hidden_at" => nil, "hidden_by_id" => nil)
      expect(log.before_after["after"]["hidden_by_id"]).to eq(admin.id)
      expect(log.before_after["after"]["hidden_at"]).to be_present
    end
  end

  describe "POST /buildings/:id/unhide as an admin" do
    let(:admin) { membership_with("admin") }

    before do
      sign_in(admin)
      building.update!(hidden_at: Time.current, hidden_by: admin)
    end

    it "unhides the building, redirects to the building, and audits the change" do
      expect {
        post unhide_building_path(building)
      }.to change(ActivityLog, :count).by(1)

      expect(response).to redirect_to(building_path(building))
      expect(flash[:notice]).to eq(I18n.t("buildings.unhide.success"))

      building.reload
      expect(building).not_to be_hidden
      expect(building.hidden_by).to be_nil

      log = ActivityLog.last
      expect(log.action).to eq("building.unhidden")
      expect(log.before_after["before"]["hidden_by_id"]).to eq(admin.id)
      expect(log.before_after["after"]).to eq("hidden_at" => nil, "hidden_by_id" => nil)
    end
  end

  describe "as a non-admin viewer" do
    it_behaves_like "an admin-only action" do
      let(:actor) { membership_with("viewer") }
      let(:http_method) { :post }
      let(:request_path) { hide_building_path(building) }
    end

    it "denies unhide too, and writes no ActivityLog" do
      viewer = membership_with("viewer")
      building.update!(hidden_at: Time.current)
      sign_in(viewer)

      expect {
        post unhide_building_path(building)
      }.not_to change(ActivityLog, :count)

      expect(response).to redirect_to(find_a_room_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_authorized"))
      expect(building.reload).to be_hidden
    end
  end
end
