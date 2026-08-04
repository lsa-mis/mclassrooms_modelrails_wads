require "rails_helper"

# MClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): admin CRUD for the
# campus_allow/building_allow/building_exclude rows that scope which rooms the
# next sync run pulls in. There is NO referential coupling to a sync run — a
# destroyed rule simply stops applying on the next run. Every mutation flows
# through Curation::Apply (spec D13), so the record write and its ActivityLog
# commit or roll back together in ONE transaction.
#
# Mirrors spec/requests/admin/announcements_spec.rb's tenancy setup and reuses
# "an admin-only action" for the denial matrix. SyncScopeRulePolicy denies
# every action to a non-admin unconditionally — no editor carve-out — so an
# editor and a plain viewer are both proven denied.
#
# Flashes are asserted by value, not merely redirected past
# (spec/code_smells/flash_messages_are_asserted_spec.rb).
RSpec.describe "Admin sync scope rules", type: :request do
  let(:workspace) { create(:workspace, slug: "sync-scope-rules-spec-workspace", personal: false) }

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

  let!(:scope_rule) do
    create(:sync_scope_rule, workspace: workspace, rule_type: "campus_allow", value: "ANNARBOR")
  end

  let(:valid_params) { { sync_scope_rule: { rule_type: "building_exclude", value: "BLDG9999" } } }

  describe "GET /admin/sync_scope_rules" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { admin_sync_scope_rules_path }
      end
    end

    it "returns 200 for an admin, listing the workspace's rules" do
      sign_in(membership_with("admin"))

      get admin_sync_scope_rules_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ANNARBOR")
    end

    # for_current_workspace (CLAUDE.md deviation #1) is what keeps another
    # workspace's rules off this page — no default_scope does it ambiently.
    it "does not list a rule belonging to another workspace" do
      foreign = create(:sync_scope_rule, value: "FOREIGNCAMPUS")
      sign_in(membership_with("admin"))

      get admin_sync_scope_rules_path

      expect(response.body).not_to include(foreign.value)
    end
  end

  describe "GET /admin/sync_scope_rules/new" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { new_admin_sync_scope_rule_path }
      end
    end

    it "returns 200 for an admin" do
      sign_in(membership_with("admin"))

      get new_admin_sync_scope_rule_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/sync_scope_rules" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :post }
        let(:request_path) { admin_sync_scope_rules_path }
        let(:request_params) { valid_params }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "creates the rule, says so, and writes exactly one audited ActivityLog row" do
        expect {
          post admin_sync_scope_rules_path, params: valid_params
        }.to change(SyncScopeRule, :count).by(1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_sync_scope_rules_path)
        expect(flash[:notice]).to eq(I18n.t("admin.sync_scope_rules.create.success"))

        # Scoped by `workspace:` explicitly rather than for_current_workspace:
        # Current.workspace is per-request and is already reset by the time
        # this runs, so the named scope would match workspace_id IS NULL.
        created = SyncScopeRule.find_by!(workspace: workspace, value: "BLDG9999")
        expect(created.rule_type).to eq("building_exclude")

        log = ActivityLog.last
        expect(log.action).to eq("sync_scope_rule.created")
        expect(log.trackable).to eq(created)
        expect(log.before_after).to be_present
      end

      it "rejects a duplicate (rule_type, value) pair with 422, no new record, and no ActivityLog" do
        duplicate = { sync_scope_rule: { rule_type: scope_rule.rule_type, value: scope_rule.value } }

        expect {
          post admin_sync_scope_rules_path, params: duplicate
        }.not_to change(SyncScopeRule, :count)
        expect {
          post admin_sync_scope_rules_path, params: duplicate
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      # The same value under a DIFFERENT rule_type is legitimate — uniqueness
      # is scoped to [:workspace_id, :rule_type], so this must not be caught
      # by the duplicate guard above.
      it "allows the same value under a different rule_type" do
        expect {
          post admin_sync_scope_rules_path,
            params: { sync_scope_rule: { rule_type: "building_allow", value: scope_rule.value } }
        }.to change(SyncScopeRule, :count).by(1)

        expect(flash[:notice]).to eq(I18n.t("admin.sync_scope_rules.create.success"))
      end

      # Assigning an out-of-enum value to a Rails `enum` raises ArgumentError
      # at ASSIGNMENT time — before Curation::Apply's own rescue
      # (RecordInvalid/RecordNotDestroyed) ever sees it — so the controller
      # checks it before the value reaches the setter. Without that guard this
      # is a 500, not a 422.
      it "rejects a crafted invalid rule_type with 422 (not 500), no new record, and no ActivityLog" do
        crafted = { sync_scope_rule: { rule_type: "not_a_type", value: "CRAFTED" } }

        expect {
          post admin_sync_scope_rules_path, params: crafted
        }.not_to change(SyncScopeRule, :count)
        expect {
          post admin_sync_scope_rules_path, params: crafted
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /admin/sync_scope_rules/:id/edit" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { edit_admin_sync_scope_rule_path(scope_rule) }
      end
    end

    it "returns 200 for an admin" do
      sign_in(membership_with("admin"))

      get edit_admin_sync_scope_rule_path(scope_rule)

      expect(response).to have_http_status(:ok)
    end

    # set_sync_scope_rule resolves through for_current_workspace, so a foreign
    # id raises RecordNotFound rather than yielding someone else's record.
    # ApplicationController#record_not_found turns that into a redirect +
    # generic alert for an HTML request (a 404 status only for
    # turbo_stream/json), so the admin learns nothing about whether that id
    # exists in some other workspace.
    it "refuses a rule belonging to another workspace, disclosing nothing" do
      foreign = create(:sync_scope_rule, value: "FOREIGNCAMPUS")
      sign_in(membership_with("admin"))

      get edit_admin_sync_scope_rule_path(foreign)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
      expect(response.body).not_to include(foreign.value)
    end
  end

  describe "PATCH /admin/sync_scope_rules/:id" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :patch }
        let(:request_path) { admin_sync_scope_rule_path(scope_rule) }
        let(:request_params) { { sync_scope_rule: { value: "DENIED" } } }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "updates the rule, says so, and writes exactly one audited ActivityLog row" do
        expect {
          patch admin_sync_scope_rule_path(scope_rule), params: { sync_scope_rule: { value: "DEARBORN" } }
        }.to change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_sync_scope_rules_path)
        expect(flash[:notice]).to eq(I18n.t("admin.sync_scope_rules.update.success"))
        expect(scope_rule.reload.value).to eq("DEARBORN")

        log = ActivityLog.last
        expect(log.action).to eq("sync_scope_rule.updated")
        expect(log.trackable).to eq(scope_rule)
        expect(log.before_after).to be_present
      end

      it "rejects a crafted invalid rule_type with 422 (not 500) and leaves the record alone" do
        expect {
          patch admin_sync_scope_rule_path(scope_rule),
            params: { sync_scope_rule: { rule_type: "not_a_type", value: "CRAFTED" } }
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(scope_rule.reload.value).to eq("ANNARBOR")
        expect(scope_rule.rule_type).to eq("campus_allow")
      end
    end
  end

  describe "DELETE /admin/sync_scope_rules/:id" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :delete }
        let(:request_path) { admin_sync_scope_rule_path(scope_rule) }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "deletes the rule, says so, and writes exactly one audited ActivityLog row" do
        expect {
          delete admin_sync_scope_rule_path(scope_rule)
        }.to change(SyncScopeRule, :count).by(-1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_sync_scope_rules_path)
        expect(flash[:notice]).to eq(I18n.t("admin.sync_scope_rules.destroy.success"))

        log = ActivityLog.last
        expect(log.action).to eq("sync_scope_rule.destroyed")
        expect(log.before_after["after"]).to be_nil
      end
    end
  end
end
