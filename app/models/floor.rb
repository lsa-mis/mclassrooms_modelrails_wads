class Floor < ApplicationRecord
  include Tenanted

  belongs_to :building
  has_many :rooms, dependent: :nullify
  has_one_attached :plan

  validates :label, presence: true, uniqueness: { scope: :building_id }
  validates :plan, content_type: [ :png, :jpeg, :webp, :pdf ],
                   size: { less_than_or_equal_to: 10.megabytes }

  # Phase 4 Task 9 (Brief §5.3): attribute-shaped remover, same species as
  # Building#remove_photo= (app/models/building.rb) and Room's Task 7
  # remove_* writers — attribute-shaped so it flows through
  # `Building#floors_attributes=` (accepts_nested_attributes_for) +
  # Curation::Apply.call(attributes:) with no separate purge call anywhere.
  def remove_plan=(value)
    plan.purge_later if ActiveModel::Type::Boolean.new.cast(value)
  end
  def remove_plan = false
end
