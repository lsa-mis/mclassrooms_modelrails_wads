class Settings::AvatarPolicy < ApplicationPolicy
  def show?
    user.present?
  end

  def update?
    user.present?
  end

  def destroy?
    user.present?
  end
end
