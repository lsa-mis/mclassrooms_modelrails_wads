class Settings::TimezonePolicy < ApplicationPolicy
  def update?
    user.present?
  end
end
