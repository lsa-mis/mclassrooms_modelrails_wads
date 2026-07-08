FactoryBot.define do
  factory :editor_assignment do
    user
    unit
    # workspace derives from :unit, not :user — User isn't Tenanted (it joins
    # workspaces through Membership), so unit.workspace is the only tenant
    # anchor available. Same landmine as spec/factories/rooms.rb: pass unit:
    # explicitly when overriding workspace, or they land in different tenants.
    workspace { unit.workspace }
  end
end
