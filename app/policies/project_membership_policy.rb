class ProjectMembershipPolicy < ApplicationPolicy
  def index?
    project_member?
  end

  def create?
    project_membership&.creator?
  end

  def update?
    project_membership&.creator? && !record_is_creator?
  end

  def destroy?
    project_membership&.creator? && !record_is_creator?
  end

  def toggle_pin?
    project_member? && record.user == user
  end

  private

  def project
    if record.is_a?(ProjectMembership)
      record.project
    else
      Current.project
    end
  end

  def project_membership
    @project_membership ||= project&.project_memberships&.find_by(user: user)
  end

  def project_member?
    project_membership.present?
  end

  def record_is_creator?
    record.creator?
  end
end
