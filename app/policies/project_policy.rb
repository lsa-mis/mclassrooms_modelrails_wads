class ProjectPolicy < ApplicationPolicy
  def index?
    membership.present?
  end

  def show?
    project_member?
  end

  def create?
    membership.present?
  end

  def update?
    project_membership&.creator?
  end

  def destroy?
    project_membership&.creator? || can?("manage_workspace")
  end

  private

  def project_membership
    @project_membership ||= record.project_memberships.find_by(user: user)
  end

  def project_member?
    project_membership.present?
  end
end
