# frozen_string_literal: true

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): admin CRUD for the
# department_group -> display_name overrides consumed wherever a unit's
# human-facing name renders (e.g. RoomSearch.unit_options,
# Admin::EditorAssignmentsController#workspace_units). UnitDisplayNamePolicy
# denies every action to a non-admin unconditionally (grant.admin? only, no
# editor carve-out), so `authorize` is unconditional here on every action,
# same shape as Admin::AnnouncementsController/Admin::EditorAssignmentsController.
#
# Every mutation flows through Curation::Apply (UnitDisplayName is
# Trackable-free by design) so the record write and its ActivityLog commit or
# roll back together, in ONE transaction (spec D13).
module Admin
  class UnitDisplayNamesController < ApplicationController
    include DirectoryScoped

    before_action :set_unit_display_name, only: [ :edit, :update, :destroy ]

    def index
      authorize UnitDisplayName
      @unit_display_names = UnitDisplayName.for_current_workspace.order(:department_group)
    end

    def new
      authorize UnitDisplayName
      @unit_display_name = UnitDisplayName.new
    end

    # `workspace: Current.workspace` assigned explicitly — UnitDisplayName is
    # Tenanted (`belongs_to :workspace`, required), and DirectoryScoped only
    # sets Current.workspace, it doesn't default a new record's association.
    # Mirrors Admin::AnnouncementsController#create's identical pattern.
    def create
      authorize UnitDisplayName
      @unit_display_name = UnitDisplayName.new(workspace: Current.workspace)
      result = Curation::Apply.call(record: @unit_display_name, actor: Current.user,
                                    action: "unit_display_name.created", attributes: unit_display_name_params)

      if result.success?
        redirect_to admin_unit_display_names_path, notice: t(".success")
      else
        # A duplicate department_group (the model's own uniqueness
        # validation, scoped to workspace_id) lands here as an ordinary
        # Result.failure — re-render :new with the model's own error attached.
        @unit_display_name = result.payload[:record] || @unit_display_name
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @unit_display_name
    end

    def update
      authorize @unit_display_name
      result = Curation::Apply.call(record: @unit_display_name, actor: Current.user,
                                    action: "unit_display_name.updated", attributes: unit_display_name_params)

      if result.success?
        redirect_to admin_unit_display_names_path, notice: t(".success")
      else
        @unit_display_name = result.payload[:record] || @unit_display_name
        render :edit, status: :unprocessable_entity
      end
    end

    # Block form (Curation::Apply's second call shape) — a destroy is not
    # plain attribute assignment, so the record + its audit row are still
    # written in the SAME transaction via the block.
    def destroy
      authorize @unit_display_name
      result = Curation::Apply.call(record: @unit_display_name, actor: Current.user,
                                    action: "unit_display_name.destroyed") { |name| name.destroy! }

      if result.success?
        redirect_to admin_unit_display_names_path, notice: t(".success")
      else
        redirect_to admin_unit_display_names_path, alert: result.errors.to_sentence
      end
    end

    private

    # for_current_workspace (CLAUDE.md deviation #1): no unscoped
    # UnitDisplayName.find, mirrors Admin::AnnouncementsController#set_announcement.
    def set_unit_display_name
      @unit_display_name = UnitDisplayName.for_current_workspace.find(params[:id])
    end

    def unit_display_name_params
      params.expect(unit_display_name: [ :department_group, :display_name ])
    end
  end
end
