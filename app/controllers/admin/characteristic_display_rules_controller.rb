# frozen_string_literal: true

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): admin CRUD for the
# icon/category-override/filterable/team-learning overrides keyed to a
# characteristic's normalized short_code (CharacteristicDisplayRule#normalize_short_code
# shares CodeNormalizer with phase 2's sync, so this join lines up with
# RoomCharacteristic.short_code). CharacteristicDisplayRulePolicy denies every
# action to a non-admin unconditionally (grant.admin? only, no editor
# carve-out), so `authorize` is unconditional here on every action, same
# shape as Admin::AnnouncementsController/Admin::EditorAssignmentsController.
#
# Every mutation flows through Curation::Apply (CharacteristicDisplayRule is
# Trackable-free by design — see the model's own header comment) so the
# record write and its ActivityLog commit or roll back together, in ONE
# transaction (spec D13).
module Admin
  class CharacteristicDisplayRulesController < ApplicationController
    include DirectoryScoped

    before_action :set_characteristic_display_rule, only: [ :edit, :update, :destroy ]

    def index
      authorize CharacteristicDisplayRule
      @characteristic_display_rules = CharacteristicDisplayRule.for_current_workspace.order(:short_code)
    end

    def new
      authorize CharacteristicDisplayRule
      @characteristic_display_rule = CharacteristicDisplayRule.new
    end

    # `workspace: Current.workspace` assigned explicitly — CharacteristicDisplayRule
    # is Tenanted (`belongs_to :workspace`, required), and DirectoryScoped only
    # sets Current.workspace, it doesn't default a new record's association.
    # Mirrors Admin::AnnouncementsController#create's identical pattern.
    def create
      authorize CharacteristicDisplayRule
      @characteristic_display_rule = CharacteristicDisplayRule.new(workspace: Current.workspace)
      result = Curation::Apply.call(record: @characteristic_display_rule, actor: Current.user,
                                    action: "characteristic_display_rule.created",
                                    attributes: characteristic_display_rule_params)

      if result.success?
        redirect_to admin_characteristic_display_rules_path, notice: t(".success")
      else
        # A duplicate short_code (the model's own uniqueness validation,
        # scoped to workspace_id) lands here as an ordinary Result.failure —
        # re-render :new with the model's own error attached.
        @characteristic_display_rule = result.payload[:record] || @characteristic_display_rule
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @characteristic_display_rule
    end

    def update
      authorize @characteristic_display_rule
      result = Curation::Apply.call(record: @characteristic_display_rule, actor: Current.user,
                                    action: "characteristic_display_rule.updated",
                                    attributes: characteristic_display_rule_params)

      if result.success?
        redirect_to admin_characteristic_display_rules_path, notice: t(".success")
      else
        @characteristic_display_rule = result.payload[:record] || @characteristic_display_rule
        render :edit, status: :unprocessable_entity
      end
    end

    # Block form (Curation::Apply's second call shape) — a destroy is not
    # plain attribute assignment, so the record + its audit row are still
    # written in the SAME transaction via the block.
    def destroy
      authorize @characteristic_display_rule
      result = Curation::Apply.call(record: @characteristic_display_rule, actor: Current.user,
                                    action: "characteristic_display_rule.destroyed") { |rule| rule.destroy! }

      if result.success?
        redirect_to admin_characteristic_display_rules_path, notice: t(".success")
      else
        redirect_to admin_characteristic_display_rules_path, alert: result.errors.to_sentence
      end
    end

    private

    # for_current_workspace (CLAUDE.md deviation #1): no unscoped
    # CharacteristicDisplayRule.find, mirrors Admin::AnnouncementsController#set_announcement.
    def set_characteristic_display_rule
      @characteristic_display_rule = CharacteristicDisplayRule.for_current_workspace.find(params[:id])
    end

    def characteristic_display_rule_params
      params.expect(characteristic_display_rule: [ :short_code, :icon_key, :category_override, :filterable, :team_learning ])
    end
  end
end
