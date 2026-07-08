FactoryBot.define do
  factory :campus do
    workspace
    sequence(:code) { |n| (100 + n).to_s }
    sequence(:description) { |n| "Campus #{n}" }
  end
end
