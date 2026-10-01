# frozen_string_literal: true

# Shared by the Sync:: phase specs. An untouched counter is absent from the hash, not present
# and zero, so #fetch(..., 0) reads both the same way.
module SyncPhaseHelpers
  def counter(phase, key) = phase.counters.fetch(key.to_s, 0)

  def stub_rooms_feed
    stub_um_get("/bf/Buildings/v2/RoomInfo/1005046", fixture: "rooms_1005046.json",
      query: { "$start_index" => "0", "$count" => "1000" })
    stub_um_get("/bf/Buildings/v2/RoomInfo/1005090", fixture: "rooms_1005090.json",
      query: { "$start_index" => "0", "$count" => "1000" })
  end
end

RSpec.configure do |config|
  config.include SyncPhaseHelpers, file_path: %r{spec/lib/sync/}
end
