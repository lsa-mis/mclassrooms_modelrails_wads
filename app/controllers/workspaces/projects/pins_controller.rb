# frozen_string_literal: true

module Workspaces
  module Projects
    # MY pin on this project, as a singular end-state resource (#686):
    # create/destroy are idempotent where the old PATCH :toggle_pin flipped
    # state, so a retried or double-submitted request silently UN-pinned.
    # Resolved through Current.user, never a URL param (IDOR) — which is why
    # the resource hangs off the project rather than a membership id.
    class PinsController < ApplicationController
      include WorkspaceScoped
      include ProjectScoped

      def create
        membership = my_membership
        authorize membership, :pin?
        membership.update!(pinned: true)
        redirect_after_pin_change
      end

      def destroy
        membership = my_membership
        authorize membership, :pin?
        membership.update!(pinned: false)
        redirect_after_pin_change
      end

      private

      def my_membership
        @project.project_memberships.find_by!(user: Current.user)
      end

      def redirect_after_pin_change
        redirect_back fallback_location: workspace_projects_path(@workspace), notice: t("workspaces.projects.pins.toggled")
      end
    end
  end
end
