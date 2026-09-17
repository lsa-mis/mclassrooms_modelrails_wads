FactoryBot.define do
  factory :invitation do
    association :invitable, factory: :workspace
    # Sequence-prefixed for the same reason as the user factory (#856): the
    # pending-invitation indexes are unique on (email, invitable), so two
    # invitations built for one workspace collide whenever Faker repeats an
    # address — improbable, not impossible, and the failure surfaces as
    # RecordInvalid on a row the failing spec never mentions.
    sequence(:email) { |n| "invite-#{n}-#{Faker::Internet.email}" }
    role { Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" } }
    invited_by factory: :user
    expires_at { 7.days.from_now }

    trait :magic_link do
      email { nil }
    end

    trait :accepted do
      status { "accepted" }
      accepted_at { Time.current }
      accepted_by factory: :user
    end

    trait :declined do
      status { "declined" }
      declined_at { Time.current }
    end

    trait :revoked do
      status { "revoked" }
      revoked_at { Time.current }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end

    # A stamped pending row with NO InvitationBlock — reachable in production
    # via the unblock residual (spec §14). Mailer-guard specs need a real
    # block row instead: the guard keys on blocked_by_invitee?, not the stamp.
    trait :suppressed do
      suppressed_at { Time.current }
    end
  end
end
