class Campus < ApplicationRecord
  include Tenanted

  validates :code, presence: true, uniqueness: { scope: :workspace_id }
end
