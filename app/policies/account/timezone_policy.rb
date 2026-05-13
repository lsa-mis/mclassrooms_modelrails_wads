class Account::TimezonePolicy < ApplicationPolicy
  def update?
    user.present?
  end
end
