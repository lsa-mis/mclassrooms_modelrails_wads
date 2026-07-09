require "rails_helper"

# Regression guard for the Phase 3 whole-branch review's "Important" finding:
# CharacteristicFilterGroups.label_for (-> labels -> fetch(:labels)) computes
# data_version on EVERY call — 4 aggregate queries (count + maximum(:updated_at)
# on both room_characteristics and characteristic_display_rules) — because
# Ruby evaluates the cache KEY (which embeds data_version) before the cache
# lookup runs. RoomsHelper#room_characteristic_icons/#room_characteristic_labels
# used to call label_for once per characteristic per row, so a 30-room results
# page thrashed data_version hundreds of times per render (Bullet can't catch
# this — it's repeated class-level aggregates, not association N+1).
#
# The fix resolves CharacteristicFilterGroups.labels ONCE per request (a
# RoomsHelper ivar memo mirroring the existing characteristic_icon_keys
# pattern) and looks codes up in the resulting hash. This spec seeds a
# workload that would explode pre-fix (10 rooms x 5 characteristics each) and
# asserts the count of data_version-forming aggregate queries stays flat
# instead of scaling with rows x characteristics.
RSpec.describe "GET /find-a-room query budget", type: :request do
  let(:workspace) { create(:workspace, slug: "rooms-query-budget-workspace", personal: false) }

  before do
    allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
    allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
  end

  # Same reuse-and-re-role pattern as spec/requests/rooms_spec.rb: `create(:user)`
  # auto-joins `workspace` via User#onboard_workspace under the stubbed :shared
  # posture, so re-role the auto-created membership instead of inserting a second.
  def membership_with(slug)
    user = create(:user)
    membership = Membership.find_by!(user: user, workspace: workspace)
    membership.update!(role: Role.system_default!(slug))
    user
  end

  # Matches the SQL CharacteristicFilterGroups.data_version issues: a COUNT or
  # MAX aggregate against either room_characteristics or
  # characteristic_display_rules. Ordinary row-fetch queries against those
  # tables (e.g. the room_characteristics preload) don't carry COUNT/MAX, so
  # they don't match.
  DATA_VERSION_AGGREGATE = /\b(COUNT|MAX)\s*\(.*(room_characteristics|characteristic_display_rules)|(room_characteristics|characteristic_display_rules).*\b(COUNT|MAX)\s*\(/i

  it "does not scale the data_version aggregate query count with rows x characteristics" do
    building = create(:building, workspace: workspace)
    # Normalization-stable (lowercase, alphanumeric-only) short_codes: RoomCharacteristic.short_code
    # is NOT model-normalized, but CodeNormalizer (used by CharacteristicDisplayRule matching and
    # by RoomSearch) downcases + strips non-alphanumerics, so a code that survives that transform
    # unchanged behaves identically to production-synced data.
    codes = %w[projector whiteboard speakers hdmiport adapter]

    create_list(:room, 10, building: building, workspace: workspace).each do |room|
      codes.each do |code|
        create(:room_characteristic, room: room, workspace: workspace, short_code: code,
                                      description: "Technology: #{code.titleize}")
      end
    end

    # One rule with a real icon_key (renders a chip via room_characteristic_icons),
    # one filterable-only rule (no chip, still resolved via room_characteristic_labels).
    create(:characteristic_display_rule, workspace: workspace, short_code: "projector", icon_key: "computer_desktop")
    create(:characteristic_display_rule, workspace: workspace, short_code: "whiteboard")

    sign_in(membership_with("viewer"))

    aggregate_query_count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if %w[CACHE SCHEMA].include?(payload[:name])
      aggregate_query_count += 1 if payload[:sql].match?(DATA_VERSION_AGGREGATE)
    end

    begin
      get find_a_room_path
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    expect(response).to have_http_status(:ok)
    # Post-fix this is a small constant (the controller's CharacteristicFilterGroups.filters
    # call plus the helper's single CharacteristicFilterGroups.labels call — 4 aggregate
    # queries apiece). Pre-fix, 10 rooms x 5 characteristics drove this into the hundreds.
    expect(aggregate_query_count).to be <= 8
  end
end
