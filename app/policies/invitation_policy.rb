class InvitationPolicy < ApplicationPolicy
  def index?
    membership.present?
  end

  def create?
    can?("manage_members")
  end

  def destroy?
    can?("manage_members")
  end

  def resend?
    can?("manage_members")
  end
end
