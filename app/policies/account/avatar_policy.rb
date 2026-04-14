class Account::AvatarPolicy < ApplicationPolicy
  def update?
    user.present?
  end
end
