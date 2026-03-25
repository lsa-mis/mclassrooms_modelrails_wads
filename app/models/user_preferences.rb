class UserPreferences < ApplicationRecord
  belongs_to :user

  THEMES = %w[light dark system].freeze

  enum :theme, THEMES.index_by(&:itself), default: "system"
end
