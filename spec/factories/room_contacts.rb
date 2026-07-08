FactoryBot.define do
  factory :room_contact do
    room
    workspace { room.workspace }
    scheduling_name { "Scheduling Office" }
    scheduling_email { "scheduling@example.edu" }
    scheduling_phone { "734-555-0100" }
    scheduling_detail_url { "https://example.edu/rooms/schedule" }
    scheduling_usage_guidelines_url { "https://example.edu/rooms/guidelines" }
    support_department_id { "1000" }
    support_department_description { "Facilities Support" }
    support_email { "support@example.edu" }
    support_phone { "734-555-0199" }
    support_url { "https://example.edu/support" }
  end
end
