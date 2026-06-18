class Settings::ThemePreferencesPolicy < ApplicationPolicy
  def edit?
    user.present?
  end

  def update?
    user.present?
  end
end
