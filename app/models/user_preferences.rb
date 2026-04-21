class UserPreferences < ApplicationRecord
  belongs_to :user

  enum :theme, { light: "light", dark: "dark", system: "system" }, default: "system"

  validates :locale, length: { maximum: 10 }, allow_nil: true
  validates :timezone, length: { maximum: 50 }, allow_nil: true
  validates :docs_mode, length: { maximum: 20 }, allow_nil: true
end
