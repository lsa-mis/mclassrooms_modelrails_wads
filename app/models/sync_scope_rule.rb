class SyncScopeRule < ApplicationRecord
  include Tenanted

  enum :rule_type, { campus_allow: "campus_allow", building_allow: "building_allow", building_exclude: "building_exclude" }

  validates :value, presence: true, uniqueness: { scope: [ :workspace_id, :rule_type ] }
end
