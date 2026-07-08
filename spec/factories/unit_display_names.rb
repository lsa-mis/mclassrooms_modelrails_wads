FactoryBot.define do
  factory :unit_display_name do
    workspace
    sequence(:department_group) { |n| "DeptGroup#{n}" }
    sequence(:display_name) { |n| "College #{n}" }
  end
end
