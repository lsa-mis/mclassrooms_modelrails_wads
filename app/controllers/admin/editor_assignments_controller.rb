# frozen_string_literal: true

# MiClassrooms Phase 5 Task 9 (Brief §14.1): admin console to grant/revoke
# unit editor claims — the last piece RoleResolver's editor grant depends on
# (app/lib/role_resolver.rb#editor_unit_ids). EditorAssignmentPolicy (Task 4)
# is admin-only end to end — an editor managing editor assignments, their own
# or anyone else's, would be a privilege-escalation vector — so `authorize`
# is unconditional here on every action, same shape as
# Admin::AnnouncementsController/Admin::BulkUploadsController.
#
# Every mutation flows through Curation::Apply (EditorAssignment is
# Trackable-free — RoleResolver's own header comment: "Consumed only by
# RoleResolver" — Curation::Apply is its sole audit writer) so the record
# write and its ActivityLog commit or roll back together, in ONE transaction
# (spec D13).
#
# TENANT SAFETY (CRITICAL): EditorAssignment is Tenanted, but a raw
# `EditorAssignment.new(editor_assignment_params)` would let an admin grant
# access to a foreign workspace's user or unit simply by crafting an id in
# the request body. `#create` resolves BOTH the user and the unit THROUGH
# the request's own workspace before the record is ever built — a kept
# member of `Current.workspace` (`workspace_members`) and a
# `Unit.for_current_workspace` row (`workspace_units_scope`) — never straight
# off `params`. A user_id/unit_id naming a foreign-tenant (or nonexistent)
# row simply resolves to nil via `find_by`, which the model's own required
# `belongs_to :user`/`belongs_to :unit` associations reject as an ordinary
# validation failure (422, re-render :new) — not a silent grant, and not a
# special-cased branch.
module Admin
  class EditorAssignmentsController < ApplicationController
    include DirectoryScoped

    before_action :set_editor_assignment, only: [ :destroy ]

    # Groups every granted assignment by its unit (only units with at least
    # one grant appear — unlike AnnouncementsController#index's fixed three
    # slots, there's no natural "empty unit" row to render here).
    # includes(:user, :unit) avoids an N+1 across the whole list.
    def index
      authorize EditorAssignment
      assignments = EditorAssignment.for_current_workspace.includes(:user, :unit)
      @assignments_by_unit = assignments.group_by(&:unit).sort_by { |unit, _| unit.display_name }
    end

    def new
      authorize EditorAssignment
      @editor_assignment = EditorAssignment.new
      @members = workspace_members
      @units = workspace_units
    end

    def create
      authorize EditorAssignment
      attrs = editor_assignment_params
      @editor_assignment = EditorAssignment.new(
        workspace: Current.workspace,
        user: workspace_members.find_by(id: attrs[:user_id]),
        unit: workspace_units_scope.find_by(id: attrs[:unit_id])
      )

      result = Curation::Apply.call(record: @editor_assignment, actor: Current.user, action: "editor_assignment.granted")

      if result.success?
        redirect_to admin_editor_assignments_path, notice: t(".success")
      else
        # A duplicate (user, unit) pair (EditorAssignment's own uniqueness
        # validation) or an unresolvable (foreign/blank) user_id/unit_id both
        # land here as an ordinary Result.failure — re-render :new with the
        # model's own errors attached.
        @editor_assignment = result.payload[:record] || @editor_assignment
        @members = workspace_members
        @units = workspace_units
        render :new, status: :unprocessable_entity
      end
    end

    # Block form (Curation::Apply's second call shape) — a revoke is not
    # plain attribute assignment, so the record + its audit row are still
    # written in the SAME transaction via the block. RoleResolver.for is
    # DB-backed on every call (no session caching), so this takes effect on
    # the revoked user's very next request automatically.
    def destroy
      authorize @editor_assignment
      result = Curation::Apply.call(record: @editor_assignment, actor: Current.user,
                                    action: "editor_assignment.revoked") { |assignment| assignment.destroy! }

      if result.success?
        redirect_to admin_editor_assignments_path, notice: t(".success")
      else
        redirect_to admin_editor_assignments_path, alert: result.errors.to_sentence
      end
    end

    private

    # for_current_workspace (CLAUDE.md deviation #1): no unscoped
    # EditorAssignment.find, mirrors Admin::AnnouncementsController#set_announcement.
    def set_editor_assignment
      @editor_assignment = EditorAssignment.for_current_workspace.find(params[:id])
    end

    # Only KEPT-membership users are grantable (brief) — a discarded
    # (deactivated) member can't be handed an editor claim from this screen,
    # and (per the tenant-safety comment above) a user with no kept
    # membership in Current.workspace at all simply isn't found here either.
    def workspace_members
      User.where(id: Current.workspace.memberships.kept.select(:user_id)).order(:first_name, :last_name)
    end

    def workspace_units_scope
      Unit.for_current_workspace
    end

    # Sorted by the human-facing display_name (mirrors RoomSearch.unit_options)
    # rather than the raw department_group — this list is small enough per
    # workspace that the extra UnitDisplayName lookup per row is not a
    # meaningful N+1 (RoomSearch.unit_options does the identical thing).
    def workspace_units
      workspace_units_scope.to_a.sort_by(&:display_name)
    end

    def editor_assignment_params
      params.expect(editor_assignment: [ :user_id, :unit_id ])
    end
  end
end
