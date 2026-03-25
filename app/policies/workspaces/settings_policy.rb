module Workspaces
  class SettingsPolicy < ApplicationPolicy
    def edit?
      can?("manage_settings")
    end

    def update?
      can?("manage_settings")
    end
  end
end
