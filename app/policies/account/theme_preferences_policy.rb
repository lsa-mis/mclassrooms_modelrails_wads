class Account::ThemePreferencesPolicy < ApplicationPolicy
  def update?
    user.present?
  end
end
