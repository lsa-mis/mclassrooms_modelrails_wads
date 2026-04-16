module Workspaces
  class BrandingPolicy < ApplicationPolicy
    def edit?
      can?("manage_settings")
    end

    def update?
      can?("manage_settings")
    end

    def destroy?
      can?("manage_settings")
    end
  end
end
