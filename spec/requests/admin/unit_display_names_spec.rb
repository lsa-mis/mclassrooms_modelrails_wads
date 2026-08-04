require "rails_helper"

# MClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): admin CRUD for the
# department_group -> display_name overrides consumed wherever a unit's
# human-facing name renders (RoomSearch.unit_options,
# Admin::EditorAssignmentsController#workspace_units). Every mutation flows
# through Curation::Apply (spec D13), so the record write and its ActivityLog
# commit or roll back together in ONE transaction.
#
# Mirrors spec/requests/admin/announcements_spec.rb's tenancy setup and reuses
# "an admin-only action" for the denial matrix. UnitDisplayNamePolicy denies
# every action to a non-admin unconditionally — no editor carve-out — so an
# editor and a plain viewer are both proven denied.
#
# Flashes are asserted by value, not merely redirected past
# (spec/code_smells/flash_messages_are_asserted_spec.rb).
RSpec.describe "Admin unit display names", type: :request do
  let(:workspace) { create(:workspace, slug: "unit-display-names-spec-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # `create(:user)` itself triggers User#onboard_workspace (after_create),
  # which — under the :shared posture stubbed above — auto-joins `workspace`
  # with TenancyConfig.shared_join_role before this method ever runs.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  def editor_actor
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: create(:unit, workspace: workspace))
    user
  end

  let!(:display_name) do
    create(:unit_display_name, workspace: workspace,
                               department_group: "LSAPHYS", display_name: "Department of Physics")
  end

  let(:valid_params) do
    { unit_display_name: { department_group: "LSACHEM", display_name: "Department of Chemistry" } }
  end

  describe "GET /admin/unit_display_names" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { admin_unit_display_names_path }
      end
    end

    it "returns 200 for an admin, listing the workspace's overrides" do
      sign_in(membership_with("admin"))

      get admin_unit_display_names_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Department of Physics")
    end

    # for_current_workspace (CLAUDE.md deviation #1) is what keeps another
    # workspace's overrides off this page — no default_scope does it ambiently.
    it "does not list an override belonging to another workspace" do
      foreign = create(:unit_display_name, display_name: "Foreign Faculty Of Elsewhere")
      sign_in(membership_with("admin"))

      get admin_unit_display_names_path

      expect(response.body).not_to include(foreign.display_name)
    end
  end

  describe "GET /admin/unit_display_names/new" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { new_admin_unit_display_name_path }
      end
    end

    it "returns 200 for an admin" do
      sign_in(membership_with("admin"))

      get new_admin_unit_display_name_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/unit_display_names" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :post }
        let(:request_path) { admin_unit_display_names_path }
        let(:request_params) { valid_params }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "creates the override, says so, and writes exactly one audited ActivityLog row" do
        expect {
          post admin_unit_display_names_path, params: valid_params
        }.to change(UnitDisplayName, :count).by(1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_unit_display_names_path)
        expect(flash[:notice]).to eq(I18n.t("admin.unit_display_names.create.success"))

        # Scoped by `workspace:` explicitly rather than for_current_workspace:
        # Current.workspace is per-request and is already reset by the time
        # this runs, so the named scope would match workspace_id IS NULL.
        created = UnitDisplayName.find_by!(workspace: workspace, department_group: "LSACHEM")
        expect(created.display_name).to eq("Department of Chemistry")

        log = ActivityLog.last
        expect(log.action).to eq("unit_display_name.created")
        expect(log.trackable).to eq(created)
        expect(log.before_after).to be_present
      end

      it "rejects a duplicate department_group with 422, no new record, and no ActivityLog" do
        duplicate = { unit_display_name: { department_group: display_name.department_group,
                                           display_name: "Physics, again" } }

        expect {
          post admin_unit_display_names_path, params: duplicate
        }.not_to change(UnitDisplayName, :count)
        expect {
          post admin_unit_display_names_path, params: duplicate
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects a blank display_name with 422 and no new record" do
        expect {
          post admin_unit_display_names_path,
            params: { unit_display_name: { department_group: "LSAMATH", display_name: "" } }
        }.not_to change(UnitDisplayName, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /admin/unit_display_names/:id/edit" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { edit_admin_unit_display_name_path(display_name) }
      end
    end

    it "returns 200 for an admin" do
      sign_in(membership_with("admin"))

      get edit_admin_unit_display_name_path(display_name)

      expect(response).to have_http_status(:ok)
    end

    # set_unit_display_name resolves through for_current_workspace, so a
    # foreign id raises RecordNotFound rather than yielding someone else's
    # record. ApplicationController#record_not_found turns that into a
    # redirect + generic alert for an HTML request (a 404 status only for
    # turbo_stream/json), so the admin learns nothing about whether that id
    # exists in some other workspace.
    it "refuses an override belonging to another workspace, disclosing nothing" do
      foreign = create(:unit_display_name, display_name: "Foreign Faculty Of Elsewhere")
      sign_in(membership_with("admin"))

      get edit_admin_unit_display_name_path(foreign)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
      expect(response.body).not_to include(foreign.display_name)
    end
  end

  describe "PATCH /admin/unit_display_names/:id" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :patch }
        let(:request_path) { admin_unit_display_name_path(display_name) }
        let(:request_params) { { unit_display_name: { display_name: "Denied edit" } } }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "updates the override, says so, and writes exactly one audited ActivityLog row" do
        expect {
          patch admin_unit_display_name_path(display_name),
            params: { unit_display_name: { display_name: "Physics & Astronomy" } }
        }.to change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_unit_display_names_path)
        expect(flash[:notice]).to eq(I18n.t("admin.unit_display_names.update.success"))
        expect(display_name.reload.display_name).to eq("Physics & Astronomy")

        log = ActivityLog.last
        expect(log.action).to eq("unit_display_name.updated")
        expect(log.trackable).to eq(display_name)
        expect(log.before_after).to be_present
      end

      it "rejects a blank display_name with 422 and leaves the record alone" do
        expect {
          patch admin_unit_display_name_path(display_name), params: { unit_display_name: { display_name: "" } }
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(display_name.reload.display_name).to eq("Department of Physics")
      end
    end
  end

  describe "DELETE /admin/unit_display_names/:id" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :delete }
        let(:request_path) { admin_unit_display_name_path(display_name) }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "deletes the override, says so, and writes exactly one audited ActivityLog row" do
        expect {
          delete admin_unit_display_name_path(display_name)
        }.to change(UnitDisplayName, :count).by(-1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_unit_display_names_path)
        expect(flash[:notice]).to eq(I18n.t("admin.unit_display_names.destroy.success"))

        log = ActivityLog.last
        expect(log.action).to eq("unit_display_name.destroyed")
        expect(log.before_after["after"]).to be_nil
      end
    end
  end
end
