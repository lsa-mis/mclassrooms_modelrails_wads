class UserPreferences < ApplicationRecord
  belongs_to :user

  enum :theme, { light: "light", dark: "dark", system: "system" }, default: "system"
end
