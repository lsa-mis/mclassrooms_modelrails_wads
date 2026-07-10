require "rails_helper"

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): admin CRUD for the three
# reference-data models — CharacteristicDisplayRule, UnitDisplayName,
# SyncScopeRule. All three policies are admin-only end to end (no editor
# carve-out — see each policy's own header comment), and every mutation
# routes through Curation::Apply (spec D13), so the record write and its
# ActivityLog commit or roll back together in ONE transaction. Mirrors
# spec/requests/admin/announcements_spec.rb's tenancy setup and reuses "an
# admin-only action" (spec/support/shared_examples/admin_only_action.rb) for
# the denial matrix.
RSpec.describe "Admin reference data", type: :request do
  let(:workspace) { create(:workspace, slug: "reference-data-spec-workspace", personal: false) }

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
  # EditorAssignment for some unit (app/lib/role_resolver.rb#editor?) — each
  # of these three policies denies this actor identically to a plain viewer
  # (no editor carve-out at all), so both actors must be proven denied
  # independently rather than assumed equivalent.
  def editor_actor
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: create(:unit, workspace: workspace))
    user
  end

  # ---------------------------------------------------------------------
  # CharacteristicDisplayRule
  # ---------------------------------------------------------------------
  describe "CharacteristicDisplayRule" do
    let!(:rule) { create(:characteristic_display_rule, workspace: workspace, short_code: "whtbrd") }

    describe "GET /admin/characteristic_display_rules" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :get }
          let(:request_path) { admin_characteristic_display_rules_path }
        end
      end

      it "returns 200 for an admin, listing existing rules" do
        sign_in(membership_with("admin"))

        get admin_characteristic_display_rules_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("whtbrd")
      end
    end

    describe "GET /admin/characteristic_display_rules/new" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :get }
          let(:request_path) { new_admin_characteristic_display_rule_path }
        end
      end

      it "returns 200 for an admin" do
        sign_in(membership_with("admin"))

        get new_admin_characteristic_display_rule_path

        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /admin/characteristic_display_rules" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :post }
          let(:request_path) { admin_characteristic_display_rules_path }
          let(:request_params) { { characteristic_display_rule: { short_code: "proj", icon_key: "wifi" } } }
        end
      end

      describe "as an admin" do
        before { sign_in(membership_with("admin")) }

        it "creates a rule and writes exactly one audited ActivityLog row" do
          expect {
            post admin_characteristic_display_rules_path,
              params: { characteristic_display_rule: { short_code: "proj", icon_key: "wifi", filterable: "1", team_learning: "0" } }
          }.to change(CharacteristicDisplayRule, :count).by(1)
            .and change(ActivityLog, :count).by(1)

          expect(response).to redirect_to(admin_characteristic_display_rules_path)

          created = CharacteristicDisplayRule.last
          expect(created.short_code).to eq("proj")
          expect(created.icon_key).to eq("wifi")

          log = ActivityLog.last
          expect(log.action).to eq("characteristic_display_rule.created")
          expect(log.trackable).to eq(created)
          expect(log.before_after).to be_present
        end

        it "rejects a duplicate short_code with 422, no new record, and no ActivityLog" do
          expect {
            post admin_characteristic_display_rules_path,
              params: { characteristic_display_rule: { short_code: "whtbrd", icon_key: "wifi" } }
          }.not_to change(CharacteristicDisplayRule, :count)
          expect {
            post admin_characteristic_display_rules_path,
              params: { characteristic_display_rule: { short_code: "whtbrd", icon_key: "wifi" } }
          }.not_to change(ActivityLog, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end

        # CodeNormalizer.normalize (app/lib/code_normalizer.rb) downcases and
        # strips every non-alphanumeric character, so "Whtbrd>25" and
        # "whtbrd25" are two visibly-different raw strings that BOTH
        # normalize to "whtbrd25" — CharacteristicDisplayRule#normalize_short_code
        # runs before_validation, so the model's uniqueness check compares the
        # normalized value, not the literal one. This proves the collision is
        # caught even when no raw string repeats verbatim.
        it "rejects a short_code that normalizes to a collision with an existing rule, with 422, no new record, and no ActivityLog" do
          create(:characteristic_display_rule, workspace: workspace, short_code: "Whtbrd>25")

          expect {
            post admin_characteristic_display_rules_path,
              params: { characteristic_display_rule: { short_code: "whtbrd25", icon_key: "wifi" } }
          }.not_to change(CharacteristicDisplayRule, :count)
          expect {
            post admin_characteristic_display_rules_path,
              params: { characteristic_display_rule: { short_code: "whtbrd25", icon_key: "wifi" } }
          }.not_to change(ActivityLog, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    describe "GET /admin/characteristic_display_rules/:id/edit" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :get }
          let(:request_path) { edit_admin_characteristic_display_rule_path(rule) }
        end
      end

      it "returns 200 for an admin" do
        sign_in(membership_with("admin"))

        get edit_admin_characteristic_display_rule_path(rule)

        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /admin/characteristic_display_rules/:id" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :patch }
          let(:request_path) { admin_characteristic_display_rule_path(rule) }
          let(:request_params) { { characteristic_display_rule: { icon_key: "printer" } } }
        end
      end

      describe "as an admin" do
        before { sign_in(membership_with("admin")) }

        it "updates the rule and writes exactly one audited ActivityLog row" do
          expect {
            patch admin_characteristic_display_rule_path(rule), params: { characteristic_display_rule: { icon_key: "printer" } }
          }.to change(ActivityLog, :count).by(1)

          expect(response).to redirect_to(admin_characteristic_display_rules_path)
          expect(rule.reload.icon_key).to eq("printer")

          log = ActivityLog.last
          expect(log.action).to eq("characteristic_display_rule.updated")
          expect(log.trackable).to eq(rule)
          expect(log.before_after).to be_present
        end

        it "rejects a duplicate-short_code update with 422 and no ActivityLog" do
          create(:characteristic_display_rule, workspace: workspace, short_code: "proj")

          expect {
            patch admin_characteristic_display_rule_path(rule), params: { characteristic_display_rule: { short_code: "proj" } }
          }.not_to change(ActivityLog, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    describe "DELETE /admin/characteristic_display_rules/:id" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :delete }
          let(:request_path) { admin_characteristic_display_rule_path(rule) }
        end
      end

      describe "as an admin" do
        before { sign_in(membership_with("admin")) }

        it "destroys the rule and writes exactly one audited ActivityLog row" do
          expect {
            delete admin_characteristic_display_rule_path(rule)
          }.to change(CharacteristicDisplayRule, :count).by(-1)
            .and change(ActivityLog, :count).by(1)

          expect(response).to redirect_to(admin_characteristic_display_rules_path)

          log = ActivityLog.last
          expect(log.action).to eq("characteristic_display_rule.destroyed")
          expect(log.before_after["after"]).to be_nil
        end
      end
    end
  end

  # ---------------------------------------------------------------------
  # UnitDisplayName
  # ---------------------------------------------------------------------
  describe "UnitDisplayName" do
    let!(:unit_display_name) { create(:unit_display_name, workspace: workspace, department_group: "ENGIN", display_name: "College of Engineering") }

    describe "GET /admin/unit_display_names" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :get }
          let(:request_path) { admin_unit_display_names_path }
        end
      end

      it "returns 200 for an admin, listing existing display names" do
        sign_in(membership_with("admin"))

        get admin_unit_display_names_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("College of Engineering")
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
          let(:request_params) { { unit_display_name: { department_group: "LSA", display_name: "College of LSA" } } }
        end
      end

      describe "as an admin" do
        before { sign_in(membership_with("admin")) }

        it "creates a display name and writes exactly one audited ActivityLog row" do
          expect {
            post admin_unit_display_names_path,
              params: { unit_display_name: { department_group: "LSA", display_name: "College of LSA" } }
          }.to change(UnitDisplayName, :count).by(1)
            .and change(ActivityLog, :count).by(1)

          expect(response).to redirect_to(admin_unit_display_names_path)

          created = UnitDisplayName.last
          expect(created.department_group).to eq("LSA")
          expect(created.display_name).to eq("College of LSA")

          log = ActivityLog.last
          expect(log.action).to eq("unit_display_name.created")
          expect(log.trackable).to eq(created)
          expect(log.before_after).to be_present
        end

        it "rejects a duplicate department_group with 422, no new record, and no ActivityLog" do
          expect {
            post admin_unit_display_names_path,
              params: { unit_display_name: { department_group: "ENGIN", display_name: "Dupe" } }
          }.not_to change(UnitDisplayName, :count)
          expect {
            post admin_unit_display_names_path,
              params: { unit_display_name: { department_group: "ENGIN", display_name: "Dupe" } }
          }.not_to change(ActivityLog, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    describe "GET /admin/unit_display_names/:id/edit" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :get }
          let(:request_path) { edit_admin_unit_display_name_path(unit_display_name) }
        end
      end

      it "returns 200 for an admin" do
        sign_in(membership_with("admin"))

        get edit_admin_unit_display_name_path(unit_display_name)

        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /admin/unit_display_names/:id" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :patch }
          let(:request_path) { admin_unit_display_name_path(unit_display_name) }
          let(:request_params) { { unit_display_name: { display_name: "Denied edit" } } }
        end
      end

      describe "as an admin" do
        before { sign_in(membership_with("admin")) }

        it "updates the display name and writes exactly one audited ActivityLog row" do
          expect {
            patch admin_unit_display_name_path(unit_display_name), params: { unit_display_name: { display_name: "College of Eng." } }
          }.to change(ActivityLog, :count).by(1)

          expect(response).to redirect_to(admin_unit_display_names_path)
          expect(unit_display_name.reload.display_name).to eq("College of Eng.")

          log = ActivityLog.last
          expect(log.action).to eq("unit_display_name.updated")
          expect(log.trackable).to eq(unit_display_name)
          expect(log.before_after).to be_present
        end

        it "rejects a duplicate-department_group update with 422 and no ActivityLog" do
          create(:unit_display_name, workspace: workspace, department_group: "LSA")

          expect {
            patch admin_unit_display_name_path(unit_display_name), params: { unit_display_name: { department_group: "LSA" } }
          }.not_to change(ActivityLog, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    describe "DELETE /admin/unit_display_names/:id" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :delete }
          let(:request_path) { admin_unit_display_name_path(unit_display_name) }
        end
      end

      describe "as an admin" do
        before { sign_in(membership_with("admin")) }

        it "destroys the display name and writes exactly one audited ActivityLog row" do
          expect {
            delete admin_unit_display_name_path(unit_display_name)
          }.to change(UnitDisplayName, :count).by(-1)
            .and change(ActivityLog, :count).by(1)

          expect(response).to redirect_to(admin_unit_display_names_path)

          log = ActivityLog.last
          expect(log.action).to eq("unit_display_name.destroyed")
          expect(log.before_after["after"]).to be_nil
        end
      end
    end
  end

  # ---------------------------------------------------------------------
  # SyncScopeRule
  # ---------------------------------------------------------------------
  describe "SyncScopeRule" do
    let!(:sync_scope_rule) { create(:sync_scope_rule, workspace: workspace, rule_type: "campus_allow", value: "ANN_ARBOR") }

    describe "GET /admin/sync_scope_rules" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :get }
          let(:request_path) { admin_sync_scope_rules_path }
        end
      end

      it "returns 200 for an admin, listing existing rules and the sync-effective warning banner" do
        sign_in(membership_with("admin"))

        get admin_sync_scope_rules_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("ANN_ARBOR")
        expect(response.body).to include(I18n.t("admin.sync_scope_rules.index.sync_effective_notice"))
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
          let(:request_params) { { sync_scope_rule: { rule_type: "building_allow", value: "MLB" } } }
        end
      end

      describe "as an admin" do
        before { sign_in(membership_with("admin")) }

        it "creates a rule and writes exactly one audited ActivityLog row" do
          expect {
            post admin_sync_scope_rules_path,
              params: { sync_scope_rule: { rule_type: "building_allow", value: "MLB" } }
          }.to change(SyncScopeRule, :count).by(1)
            .and change(ActivityLog, :count).by(1)

          expect(response).to redirect_to(admin_sync_scope_rules_path)

          created = SyncScopeRule.last
          expect(created.rule_type).to eq("building_allow")
          expect(created.value).to eq("MLB")

          log = ActivityLog.last
          expect(log.action).to eq("sync_scope_rule.created")
          expect(log.trackable).to eq(created)
          expect(log.before_after).to be_present
        end

        it "rejects a duplicate (rule_type, value) pair with 422, no new record, and no ActivityLog" do
          expect {
            post admin_sync_scope_rules_path,
              params: { sync_scope_rule: { rule_type: "campus_allow", value: "ANN_ARBOR" } }
          }.not_to change(SyncScopeRule, :count)
          expect {
            post admin_sync_scope_rules_path,
              params: { sync_scope_rule: { rule_type: "campus_allow", value: "ANN_ARBOR" } }
          }.not_to change(ActivityLog, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end

        # Assigning an out-of-enum value to a Rails `enum` raises ArgumentError
        # at ASSIGNMENT time — before Curation::Apply's own rescue
        # (ActiveRecord::RecordInvalid/RecordNotDestroyed) ever sees it — so a
        # crafted rule_type must be caught by the controller before it ever
        # reaches the enum setter, or this would 500 instead of 422.
        it "rejects a crafted invalid rule_type with 422 (not 500), no new record, and no ActivityLog" do
          expect {
            post admin_sync_scope_rules_path,
              params: { sync_scope_rule: { rule_type: "not_a_type", value: "MLB" } }
          }.not_to change(SyncScopeRule, :count)
          expect {
            post admin_sync_scope_rules_path,
              params: { sync_scope_rule: { rule_type: "not_a_type", value: "MLB" } }
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
          let(:request_path) { edit_admin_sync_scope_rule_path(sync_scope_rule) }
        end
      end

      it "returns 200 for an admin" do
        sign_in(membership_with("admin"))

        get edit_admin_sync_scope_rule_path(sync_scope_rule)

        expect(response).to have_http_status(:ok)
      end
    end

    describe "PATCH /admin/sync_scope_rules/:id" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :patch }
          let(:request_path) { admin_sync_scope_rule_path(sync_scope_rule) }
          let(:request_params) { { sync_scope_rule: { value: "DENIED" } } }
        end
      end

      describe "as an admin" do
        before { sign_in(membership_with("admin")) }

        it "updates the rule and writes exactly one audited ActivityLog row" do
          expect {
            patch admin_sync_scope_rule_path(sync_scope_rule), params: { sync_scope_rule: { value: "YPSILANTI" } }
          }.to change(ActivityLog, :count).by(1)

          expect(response).to redirect_to(admin_sync_scope_rules_path)
          expect(sync_scope_rule.reload.value).to eq("YPSILANTI")

          log = ActivityLog.last
          expect(log.action).to eq("sync_scope_rule.updated")
          expect(log.trackable).to eq(sync_scope_rule)
          expect(log.before_after).to be_present
        end

        it "rejects a duplicate (rule_type, value) update with 422 and no ActivityLog" do
          create(:sync_scope_rule, workspace: workspace, rule_type: "campus_allow", value: "DEARBORN")

          expect {
            patch admin_sync_scope_rule_path(sync_scope_rule), params: { sync_scope_rule: { value: "DEARBORN" } }
          }.not_to change(ActivityLog, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    describe "DELETE /admin/sync_scope_rules/:id" do
      %i[viewer editor].each do |role|
        it_behaves_like "an admin-only action" do
          let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
          let(:http_method) { :delete }
          let(:request_path) { admin_sync_scope_rule_path(sync_scope_rule) }
        end
      end

      describe "as an admin" do
        before { sign_in(membership_with("admin")) }

        # No referential coupling (Brief §11.4/roadmap): destroying a
        # SyncScopeRule succeeds outright — the next sync run simply reads
        # whatever rules remain, there is no dependent record to block on.
        it "destroys the rule (no referential coupling) and writes exactly one audited ActivityLog row" do
          expect {
            delete admin_sync_scope_rule_path(sync_scope_rule)
          }.to change(SyncScopeRule, :count).by(-1)
            .and change(ActivityLog, :count).by(1)

          expect(response).to redirect_to(admin_sync_scope_rules_path)

          log = ActivityLog.last
          expect(log.action).to eq("sync_scope_rule.destroyed")
          expect(log.before_after["after"]).to be_nil
        end
      end
    end
  end
end
