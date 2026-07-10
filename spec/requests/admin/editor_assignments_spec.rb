require "rails_helper"

# MiClassrooms Phase 5 Task 9 (Brief §14.1): admin UI to grant/revoke unit
# editor claims. Every mutation flows through Curation::Apply (spec D13) —
# EditorAssignment is Trackable-free (RoleResolver's own header: "Consumed
# only by RoleResolver") — so the grant/revoke and its ActivityLog commit or
# roll back together in ONE transaction, mirroring
# spec/requests/admin/announcements_spec.rb's setup and reusing "an
# admin-only action" (spec/support/shared_examples/admin_only_action.rb) for
# the denial matrix. EditorAssignmentPolicy (Task 4) is admin-only end to
# end — no editor carve-out (an editor managing editor assignments, their
# own or anyone else's, would be a privilege-escalation vector) — so both an
# editor and a plain viewer must be proven denied independently.
RSpec.describe "Admin editor assignments", type: :request do
  let(:workspace) { create(:workspace, slug: "editor-assignments-spec-workspace", personal: false) }
  let(:unit) { create(:unit, workspace: workspace) }
  let(:member) { membership_with("viewer") }

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
  # EditorAssignment for some unit (app/lib/role_resolver.rb#editor?) — on a
  # unit UNRELATED to the resource under test in these specs, since
  # EditorAssignmentPolicy denies this actor identically to a plain viewer
  # (no editor carve-out at all).
  def editor_actor
    user = membership_with("viewer")
    create(:editor_assignment, user: user, unit: create(:unit, workspace: workspace))
    user
  end

  # A genuinely cross-tenant user: their only kept membership is in a
  # DIFFERENT workspace, never `workspace`. Built by temporarily repointing
  # the shared-workspace stub during onboarding — User#onboard_workspace,
  # under :shared, auto-joins whatever TenancyConfig.shared_workspace_slug
  # resolves to at creation time (app/lib/tenancy_config.rb reads the stub
  # fresh on every call, no memoization) — then restoring it before the
  # actual request under test runs.
  def foreign_user
    other = create(:workspace, slug: "editor-assignments-other-workspace", personal: false)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(other.slug)
    user = create(:user)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
    user
  end

  describe "GET /admin/editor_assignments" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { admin_editor_assignments_path }
      end
    end

    it "returns 200 for an admin, grouping granted assignments by unit" do
      sign_in(membership_with("admin"))
      create(:editor_assignment, user: member, unit: unit, workspace: workspace)

      get admin_editor_assignments_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(unit.display_name)
      expect(response.body).to include(member.full_name)
    end
  end

  describe "GET /admin/editor_assignments/new" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :get }
        let(:request_path) { new_admin_editor_assignment_path }
      end
    end

    it "returns 200 for an admin, offering the kept member and the unit as choices" do
      sign_in(membership_with("admin"))
      unit # force creation
      member # force creation

      get new_admin_editor_assignment_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(unit.display_name)
      expect(response.body).to include(member.full_name)
    end
  end

  describe "POST /admin/editor_assignments" do
    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :post }
        let(:request_path) { admin_editor_assignments_path }
        let(:request_params) { { editor_assignment: { user_id: member.id, unit_id: unit.id } } }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "grants a (user, unit) pair and writes exactly one audited editor_assignment.granted ActivityLog row" do
        member_id = member.id # force creation before the block below (Membership is Trackable)
        unit_id = unit.id # force creation before the block below

        expect {
          post admin_editor_assignments_path, params: { editor_assignment: { user_id: member_id, unit_id: unit_id } }
        }.to change(EditorAssignment, :count).by(1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_editor_assignments_path)

        created = EditorAssignment.last
        expect(created.user).to eq(member)
        expect(created.unit).to eq(unit)

        log = ActivityLog.last
        expect(log.action).to eq("editor_assignment.granted")
        expect(log.trackable).to eq(created)
        expect(log.before_after).to be_present
      end

      it "rejects a duplicate (user, unit) pair with 422, no new record, and no ActivityLog" do
        create(:editor_assignment, user: member, unit: unit, workspace: workspace)

        expect {
          post admin_editor_assignments_path, params: { editor_assignment: { user_id: member.id, unit_id: unit.id } }
        }.not_to change(EditorAssignment, :count)
        expect {
          post admin_editor_assignments_path, params: { editor_assignment: { user_id: member.id, unit_id: unit.id } }
        }.not_to change(ActivityLog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects a create naming a unit outside the current workspace, without granting it" do
        foreign_unit = create(:unit) # its own throwaway workspace, never `workspace`

        expect {
          post admin_editor_assignments_path,
            params: { editor_assignment: { user_id: member.id, unit_id: foreign_unit.id } }
        }.not_to change(EditorAssignment, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(EditorAssignment.where(unit_id: foreign_unit.id)).not_to exist
      end

      it "rejects a create naming a user outside the current workspace, without granting it" do
        outsider = foreign_user

        expect {
          post admin_editor_assignments_path,
            params: { editor_assignment: { user_id: outsider.id, unit_id: unit.id } }
        }.not_to change(EditorAssignment, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(EditorAssignment.where(user_id: outsider.id)).not_to exist
      end
    end
  end

  describe "DELETE /admin/editor_assignments/:id" do
    let!(:assignment) { create(:editor_assignment, user: member, unit: unit, workspace: workspace) }

    %i[viewer editor].each do |role|
      it_behaves_like "an admin-only action" do
        let(:actor) { role == :editor ? editor_actor : membership_with("viewer") }
        let(:http_method) { :delete }
        let(:request_path) { admin_editor_assignment_path(assignment) }
      end
    end

    describe "as an admin" do
      before { sign_in(membership_with("admin")) }

      it "revokes the assignment and writes exactly one audited editor_assignment.revoked ActivityLog row" do
        expect {
          delete admin_editor_assignment_path(assignment)
        }.to change(EditorAssignment, :count).by(-1)
          .and change(ActivityLog, :count).by(1)

        expect(response).to redirect_to(admin_editor_assignments_path)

        log = ActivityLog.last
        expect(log.action).to eq("editor_assignment.revoked")
        expect(log.before_after["after"]).to be_nil
      end

      # RoleResolver.for is DB-backed on EVERY call (app/lib/role_resolver.rb,
      # no session caching) — so a revoke's effect is immediate: the very
      # next RoleResolver.for(user) call resolves editor? false and
      # editor_unit_ids no longer includes the revoked unit, with no cache to
      # bust.
      it "takes immediate effect: the revoked user's editor? resolves false right after, no session caching" do
        expect(RoleResolver.for(member).editor?).to be true
        expect(RoleResolver.for(member).editor_unit_ids).to include(unit.id)

        delete admin_editor_assignment_path(assignment)

        expect(RoleResolver.for(member).editor?).to be false
        expect(RoleResolver.for(member).editor_unit_ids).not_to include(unit.id)
      end
    end
  end
end
