class WorkspaceJoinLinkPolicy < ApplicationPolicy
  # Managing the join link (creating, rotating, revoking) is a
  # workspace-settings operation — same permission gate as invitations
  # and other workspace-admin actions.
  def index?
    can?("manage_settings")
  end

  def create?
    can?("manage_settings")
  end

  def destroy?
    can?("manage_settings")
  end
end
