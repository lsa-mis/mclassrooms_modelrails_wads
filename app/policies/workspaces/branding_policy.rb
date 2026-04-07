module Workspaces
  class BrandingPolicy < ApplicationPolicy
    def edit?
      can?("manage_settings")
    end

    def update?
      can?("manage_settings")
    end

    def crop?
      can?("manage_settings")
    end

    def save_crop?
      can?("manage_settings")
    end
  end
end
