require "rails_helper"

# MiClassrooms Phase 5 Task 8 (Brief §14.1): admin CRUD for the three fixed
# announcement slots (home_page/find_a_room_page/about_page) — every mutation
# routes through Curation::Apply (spec D13), so the record write and its
# ActivityLog commit or roll back together. Mirrors
# spec/requests/admin/bulk_uploads_spec.rb's tenancy setup and reuses "an
# admin-only action" (spec/support/shared_examples/admin_only_action.rb) for
# the denial matrix.
RSpec.describe "Admin announcements", type: :request do
  let(:workspace) { create(:workspace, slug: "announcements-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # `create(:user)` itself triggers User#onboard_workspace (after_create),
  # which — under the :shared posture stubbed above — auto-joins `workspace`
  # with TenancyConfig.shared_join_role before this method ever runs. Reuses
  # and re-roles that auto-created membership instead of inserting a second
  # one for the same (user, workspace) pair.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  # An "editor" per RoleResolver is a viewer-role Membership PLUS an
  # EditorAssignment for some unit (app/lib/role_resolver.rb#editor?) —
  # AnnouncementPolicy denies this actor identically to a plain viewer (no
  # editor carve-out at all — see the policy's own header comment), so both
  # actors must be proven denied independently rather than assumed
  # equivalent.
  def editor_actor
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: create(:unit, workspace: workspace))
    user
  end

  let!(:announcement) { create(:announcement, workspace: workspace, slot: "home_page", body: "Welcome") }

  describe "GET /admin/announcements" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { admin_announcements_path }
      end
    end

    it "returns 200 for an admin, listing all three slots' filled/empty state" do
      sign_in(membership_with("admin"))

      get admin_announcements_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("announcements.slots.home_page"))
      expect(response.body).to include(I18n.t("announcements.slots.find_a_room_page"))
      expect(response.body).to include(I18n.t("announcements.slots.about_page"))
    end
  end

  describe "GET /admin/announcements/new" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { new_admin_announcement_path }
      end
    end

    it "offers only the unfilled slots for an admin (home_page is already filled)" do
      sign_in(membership_with("admin"))

      get new_admin_announcement_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("announcements.slots.find_a_room_page"))
      expect(response.body).to include(I18n.t("announcements.slots.about_page"))
      expect(response.body).not_to include(
        "value=\"home_page\"" # the already-filled slot is never an option in the picker
      )
    end
  end

  describe "POST /admin/announcements" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :post }
        let(:request_path) { admin_announcements_path }
        let(:request_params) { { announcement: { slot: "about_page", body: "About us" } } }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "fills an unfilled slot and writes exactly one audited ActivityLog row" do
        expect {
          post admin_announcements_path, params: { announcement: { slot: "about_page", body: "About us" } }
        }.to change(Announcement, :count).by(1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_announcements_path)

        created = Announcement.for(:about_page)
        expect(created.body.to_plain_text).to eq("About us")

        log = ActivityLog.last
        expect(log.action).to eq("announcement.created")
        expect(log.trackable).to eq(created)
        expect(log.before_after).to be_present
      end

      it "rejects a duplicate-slot create with 422, no new record, and no ActivityLog" do
        expect {
          post admin_announcements_path, params: { announcement: { slot: "home_page", body: "Duplicate" } }
        }.not_to change(Announcement, :count)
        expect {
          post admin_announcements_path, params: { announcement: { slot: "home_page", body: "Duplicate" } }
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      # Assigning an out-of-enum value to a Rails `enum` raises ArgumentError
      # at ASSIGNMENT time — before Curation::Apply's own rescue
      # (ActiveRecord::RecordInvalid/RecordNotDestroyed) ever sees it — so a
      # crafted slot must be caught by the controller before it ever reaches
      # the enum setter, or this would 500 instead of 422.
      it "rejects a crafted invalid slot with 422 (not 500), no new record, and no ActivityLog" do
        expect {
          post admin_announcements_path, params: { announcement: { slot: "not_a_slot", body: "Crafted" } }
        }.not_to change(Announcement, :count)
        expect {
          post admin_announcements_path, params: { announcement: { slot: "not_a_slot", body: "Crafted" } }
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /admin/announcements/:id/edit" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { edit_admin_announcement_path(announcement) }
      end
    end

    it "returns 200 for an admin" do
      sign_in(membership_with("admin"))

      get edit_admin_announcement_path(announcement)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /admin/announcements/:id" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :patch }
        let(:request_path) { admin_announcement_path(announcement) }
        let(:request_params) { { announcement: { body: "Denied edit" } } }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "edits the body and writes exactly one audited ActivityLog row" do
        expect {
          patch admin_announcement_path(announcement), params: { announcement: { body: "Updated welcome" } }
        }.to change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_announcements_path)
        expect(announcement.reload.body.to_plain_text).to eq("Updated welcome")

        log = ActivityLog.last
        expect(log.action).to eq("announcement.updated")
        expect(log.trackable).to eq(announcement)
        expect(log.before_after).to be_present
      end
    end
  end

  describe "DELETE /admin/announcements/:id" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :delete }
        let(:request_path) { admin_announcement_path(announcement) }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "destroys the announcement and writes exactly one audited ActivityLog row" do
        expect {
          delete admin_announcement_path(announcement)
        }.to change(Announcement, :count).by(-1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_announcements_path)
        expect(Announcement.for(:home_page)).to be_nil

        log = ActivityLog.last
        expect(log.action).to eq("announcement.destroyed")
        expect(log.before_after["after"]).to be_nil
      end
    end
  end

  # Brief §14.1 (optional): the shared banner partial no-ops on nil and
  # renders when the slot is filled — proven here on the home page since
  # `let!(:announcement)` above is the home_page slot.
  describe "the home page banner" do
    it "renders the home_page announcement's body" do
      get root_path

      expect(response.body).to include("Welcome")
      expect(response.body).to include(I18n.t("announcements.banner.aria_label"))
    end

    it "renders nothing when no home_page announcement exists" do
      announcement.destroy!

      get root_path

      expect(response.body).not_to include(I18n.t("announcements.banner.aria_label"))
    end
  end
end
