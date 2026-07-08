class CharacteristicDisplayRule < ApplicationRecord
  include Tenanted

  validates :short_code, presence: true, uniqueness: { scope: :workspace_id }
end
