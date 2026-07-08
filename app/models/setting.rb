# Global key-value store — NOT Tenanted. D12's capacity bound is app-level
# config under this template's single shared workspace, so a per-workspace
# settings table would be indirection with no payoff (roadmap Settings
# section, ratified in planning).
class Setting < ApplicationRecord
  CAPACITY_FILTER_MAX_DEFAULT = 50

  validates :key, presence: true, uniqueness: true

  def self.fetch(key) = find_by(key: key)&.value

  def self.put(key, value)
    find_or_initialize_by(key: key).update!(value: value.to_s)
    value
  end

  def self.capacity_filter_max
    (fetch("capacity_filter_max") || CAPACITY_FILTER_MAX_DEFAULT).to_i
  end

  def self.capacity_filter_max=(value)
    put("capacity_filter_max", Integer(value))
  end

  # Recomputed after each successful facility-ids sync phase (D12). Only
  # listed classrooms drive the bound (Room.classroom, Task 5's D8 scope) —
  # a huge lab or storage room must not inflate the filter's upper bound.
  # Zero classrooms (max nil -> 0) rounds to 0, which would render the
  # capacity slider unusable; fall back to the default instead of storing 0.
  def self.recompute_capacity_filter_max!
    max_seats = Room.classroom.maximum(:instructional_seat_count) || 0
    computed = (max_seats / 25.0).ceil * 25
    new_value = computed.zero? ? CAPACITY_FILTER_MAX_DEFAULT : computed
    self.capacity_filter_max = new_value
    new_value
  end
end
