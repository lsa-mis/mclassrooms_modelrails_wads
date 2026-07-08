class Floor < ApplicationRecord
  include Tenanted

  belongs_to :building
  has_many :rooms, dependent: :nullify
  has_one_attached :plan

  validates :label, presence: true, uniqueness: { scope: :building_id }
  validates :plan, content_type: [ :png, :jpeg, :webp, :pdf ],
                   size: { less_than_or_equal_to: 10.megabytes }
end
