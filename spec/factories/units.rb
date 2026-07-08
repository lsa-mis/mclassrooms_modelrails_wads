FactoryBot.define do
  factory :unit do
    workspace
    sequence(:department_group) { |n| "DEPT_GROUP_#{n}" }
    sequence(:description) { |n| "Unit #{n}" }
  end
end
