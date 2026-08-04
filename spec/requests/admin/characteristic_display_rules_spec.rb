require "rails_helper"

# MClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): admin CRUD for the
# icon/category-override/filterable/team-learning overrides keyed to a
# characteristic's normalized short_code. Every mutation flows through
# Curation::Apply (spec D13), so the record write and its ActivityLog commit
# or roll back together in ONE transaction.
#
# Mirrors spec/requests/admin/announcements_spec.rb's tenancy setup and reuses
# "an admin-only action" (spec/support/shared_examples/admin_only_action.rb)
# for the denial matrix. CharacteristicDisplayRulePolicy denies every action
# to a non-admin unconditionally — no editor carve-out — so an editor and a
# plain viewer are both proven denied rather than assumed equivalent.
#
# Flashes are asserted by value, not merely redirected past: a redirect-only
# assertion cannot tell a wrong locale key from a right one
# (spec/code_smells/flash_messages_are_asserted_spec.rb).
RSpec.describe "Admin characteristic display rules", type: :request do
  let(:workspace) { create(:workspace, slug: "characteristic-rules-spec-workspace", personal: false) }

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
  # EditorAssignment for some unit (app/lib/role_resolver.rb#editor?).
  def editor_actor
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: create(:unit, workspace: workspace))
    user
  end

  # CodeNormalizer downcases and strips every non-alphanumeric character, so
  # what goes in as "PHYSLAB" is stored — and rendered — as "physlab". Chosen
  # to be distinctive: asserting on a short code that collides with an
  # icon_key ("wifi") would pass on the wrong substring.
  let!(:rule) { create(:characteristic_display_rule, workspace: workspace, short_code: "PHYSLAB", icon_key: "wifi") }

  let(:valid_params) do
    { characteristic_display_rule: { short_code: "PROJ", icon_key: "projector",
                                     category_override: "Technology", filterable: "1", team_learning: "0" } }
  end

  describe "GET /admin/characteristic_display_rules" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { admin_characteristic_display_rules_path }
      end
    end

    it "returns 200 for an admin, listing the workspace's rules" do
      sign_in(membership_with("admin"))

      get admin_characteristic_display_rules_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("physlab")
    end

    # for_current_workspace (CLAUDE.md deviation #1) is what keeps another
    # workspace's overrides off this page — there is no default_scope doing it
    # ambiently, so the scope has to be proven.
    it "does not list a rule belonging to another workspace" do
      foreign = create(:characteristic_display_rule, short_code: "FOREIGNCODE")
      sign_in(membership_with("admin"))

      get admin_characteristic_display_rules_path

      expect(response.body).not_to include(foreign.short_code)
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
        let(:request_params) { valid_params }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "creates the rule, says so, and writes exactly one audited ActivityLog row" do
        expect {
          post admin_characteristic_display_rules_path, params: valid_params
        }.to change(CharacteristicDisplayRule, :count).by(1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_characteristic_display_rules_path)
        expect(flash[:notice]).to eq(I18n.t("admin.characteristic_display_rules.create.success"))

        # Scoped by `workspace:` explicitly rather than for_current_workspace:
        # Current.workspace is per-request and is already reset by the time
        # this runs, so the named scope would match workspace_id IS NULL.
        created = CharacteristicDisplayRule.find_by!(workspace: workspace, short_code: "proj")
        expect(created.icon_key).to eq("projector")

        log = ActivityLog.last
        expect(log.action).to eq("characteristic_display_rule.created")
        expect(log.trackable).to eq(created)
        expect(log.before_after).to be_present
      end

      it "rejects a duplicate short_code with 422, no new record, and no ActivityLog" do
        duplicate = { characteristic_display_rule: { short_code: rule.short_code, icon_key: "wifi" } }

        expect {
          post admin_characteristic_display_rules_path, params: duplicate
        }.not_to change(CharacteristicDisplayRule, :count)
        expect {
          post admin_characteristic_display_rules_path, params: duplicate
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

    # set_characteristic_display_rule resolves through for_current_workspace,
    # so a foreign id raises RecordNotFound rather than yielding someone
    # else's record. ApplicationController#record_not_found turns that into a
    # redirect + generic alert for an HTML request (a 404 status only for
    # turbo_stream/json), so the admin learns nothing about whether that id
    # exists in some other workspace.
    it "refuses a rule belonging to another workspace, disclosing nothing" do
      foreign = create(:characteristic_display_rule, short_code: "FOREIGNCODE")
      sign_in(membership_with("admin"))

      get edit_admin_characteristic_display_rule_path(foreign)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("errors.not_found"))
      expect(response.body).not_to include(foreign.short_code)
    end
  end

  describe "PATCH /admin/characteristic_display_rules/:id" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :patch }
        let(:request_path) { admin_characteristic_display_rule_path(rule) }
        let(:request_params) { { characteristic_display_rule: { icon_key: "denied" } } }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "updates the rule, says so, and writes exactly one audited ActivityLog row" do
        expect {
          patch admin_characteristic_display_rule_path(rule),
            params: { characteristic_display_rule: { icon_key: "projector" } }
        }.to change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_characteristic_display_rules_path)
        expect(flash[:notice]).to eq(I18n.t("admin.characteristic_display_rules.update.success"))
        expect(rule.reload.icon_key).to eq("projector")

        log = ActivityLog.last
        expect(log.action).to eq("characteristic_display_rule.updated")
        expect(log.trackable).to eq(rule)
        expect(log.before_after).to be_present
      end

      it "rejects a blank short_code with 422 and leaves the record alone" do
        expect {
          patch admin_characteristic_display_rule_path(rule),
            params: { characteristic_display_rule: { short_code: "" } }
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(rule.reload.short_code).to eq("physlab")
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

      it "deletes the rule, says so, and writes exactly one audited ActivityLog row" do
        expect {
          delete admin_characteristic_display_rule_path(rule)
        }.to change(CharacteristicDisplayRule, :count).by(-1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_characteristic_display_rules_path)
        expect(flash[:notice]).to eq(I18n.t("admin.characteristic_display_rules.destroy.success"))

        log = ActivityLog.last
        expect(log.action).to eq("characteristic_display_rule.destroyed")
        expect(log.before_after["after"]).to be_nil
      end
    end
  end
end
