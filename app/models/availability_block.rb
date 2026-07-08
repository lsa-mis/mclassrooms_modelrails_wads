class AvailabilityBlock < ApplicationRecord
  include Tenanted

  # D11: this model exists to show busy/free state ONLY. Schema has room_id +
  # starts_at/ends_at and nothing else — no title, course, instructor, or
  # description column may ever be added here; see the column-tripwire spec.
  belongs_to :room

  validates :starts_at, presence: true
  validates :ends_at, presence: true
  validate :ends_at_after_starts_at

  private

  def ends_at_after_starts_at
    return if starts_at.blank? || ends_at.blank?
    errors.add(:ends_at, "must be after starts_at") unless ends_at > starts_at
  end
end
