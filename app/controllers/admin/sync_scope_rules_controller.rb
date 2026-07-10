# frozen_string_literal: true

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): admin CRUD for the
# campus_allow/building_allow/building_exclude rows that scope which rooms
# the next sync run pulls in. There is NO referential coupling to a sync
# run — a destroyed rule simply stops applying on the next run
# (Brief/roadmap: "the next sync run simply uses the remaining rules").
# SyncScopeRulePolicy denies every action to a non-admin unconditionally
# (grant.admin? only, no editor carve-out), so `authorize` is unconditional
# here on every action, same shape as
# Admin::AnnouncementsController/Admin::EditorAssignmentsController.
#
# Every mutation flows through Curation::Apply (SyncScopeRule is
# Trackable-free by design) so the record write and its ActivityLog commit or
# roll back together, in ONE transaction (spec D13).
module Admin
  class SyncScopeRulesController < ApplicationController
    include DirectoryScoped

    before_action :set_sync_scope_rule, only: [ :edit, :update, :destroy ]

    def index
      authorize SyncScopeRule
      @sync_scope_rules = SyncScopeRule.for_current_workspace.order(:rule_type, :value)
    end

    def new
      authorize SyncScopeRule
      @sync_scope_rule = SyncScopeRule.new
    end

    # `workspace: Current.workspace` assigned explicitly — SyncScopeRule is
    # Tenanted (`belongs_to :workspace`, required), and DirectoryScoped only
    # sets Current.workspace, it doesn't default a new record's association.
    # Mirrors Admin::AnnouncementsController#create's identical pattern.
    def create
      authorize SyncScopeRule
      @sync_scope_rule = SyncScopeRule.new(workspace: Current.workspace)
      result = Curation::Apply.call(record: @sync_scope_rule, actor: Current.user,
                                    action: "sync_scope_rule.created", attributes: sync_scope_rule_params)

      if result.success?
        redirect_to admin_sync_scope_rules_path, notice: t(".success")
      else
        # A duplicate (rule_type, value) pair (the model's own uniqueness
        # validation, scoped to [:workspace_id, :rule_type]) lands here as an
        # ordinary Result.failure — re-render :new with the model's own
        # error attached.
        @sync_scope_rule = result.payload[:record] || @sync_scope_rule
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @sync_scope_rule
    end

    def update
      authorize @sync_scope_rule
      result = Curation::Apply.call(record: @sync_scope_rule, actor: Current.user,
                                    action: "sync_scope_rule.updated", attributes: sync_scope_rule_params)

      if result.success?
        redirect_to admin_sync_scope_rules_path, notice: t(".success")
      else
        @sync_scope_rule = result.payload[:record] || @sync_scope_rule
        render :edit, status: :unprocessable_entity
      end
    end

    # Block form (Curation::Apply's second call shape) — a destroy is not
    # plain attribute assignment, so the record + its audit row are still
    # written in the SAME transaction via the block. No referential
    # coupling: the next sync run simply reads the remaining rules.
    def destroy
      authorize @sync_scope_rule
      result = Curation::Apply.call(record: @sync_scope_rule, actor: Current.user,
                                    action: "sync_scope_rule.destroyed") { |rule| rule.destroy! }

      if result.success?
        redirect_to admin_sync_scope_rules_path, notice: t(".success")
      else
        redirect_to admin_sync_scope_rules_path, alert: result.errors.to_sentence
      end
    end

    private

    # for_current_workspace (CLAUDE.md deviation #1): no unscoped
    # SyncScopeRule.find, mirrors Admin::AnnouncementsController#set_announcement.
    def set_sync_scope_rule
      @sync_scope_rule = SyncScopeRule.for_current_workspace.find(params[:id])
    end

    def sync_scope_rule_params
      params.expect(sync_scope_rule: [ :rule_type, :value ])
    end
  end
end
