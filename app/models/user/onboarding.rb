class User < ApplicationRecord
  # Where a new user lands: a personal workspace, the instance's shared one, or
  # nowhere, per the tenancy preset. See /docs/developer/presets.
  module Onboarding
    extend ActiveSupport::Concern

    included do
      after_create :onboard_workspace
    end

    def onboarded?
      onboarded_at.present?
    end

    # The step is derived from data; only onboarded_at persists. See /docs/developer/presets.
    def onboarding_workspace
      workspaces.kept.first
    end

    # Fork: onboarding is single-step (just a workspace, no project/team
    # steps), so this is always :workspace — kept as a method (not a
    # constant) so it stays the same shape upstream's is derived from.
    def onboarding_step
      :workspace
    end

    # Read side of the unique partial index that enforces at most one personal workspace per user.
    def personal_workspace
      return nil if personal_workspace_id.nil?
      Workspace.kept.find_by(id: personal_workspace_id)
    end

    private

    # The contract per preset: /docs/developer/presets.
    def onboard_workspace
      case TenancyConfig.onboarding
      when :personal then create_personal_workspace
      when :shared   then join_shared_workspace
      when :none     then skip_workspace_creation
      end
    end

    def skip_workspace_creation
    end

    def create_personal_workspace
      return if personal_workspace_id.present?

      workspace = Workspace.create!(name: "#{first_name}'s Workspace", personal: true)
      owner_role = Role.system_default!("owner")
      workspace.memberships.create!(user: self, role: owner_role)
      update_column(:personal_workspace_id, workspace.id)
    end

    # Fork: the join role is configurable (TenancyConfig.shared_join_role),
    # not hardcoded to "member" — MClassrooms joins viewers by default.
    def join_shared_workspace
      workspace = TenancyConfig.shared_workspace
      raise "Shared workspace #{TenancyConfig.shared_workspace_slug.inspect} not found — has the tenancy seed run?" unless workspace
      # Return, never raise: this runs inside the after_create transaction and a raise would roll back registration.
      return unless workspace.admittable?

      join_role = Role.system_default!(TenancyConfig.shared_join_role)
      # self_join: :onboarding — see Membership#self_join and /docs/developer/notifications (The actor rule).
      workspace.memberships.create!(user: self, role: join_role, self_join: :onboarding)
    end
  end
end
