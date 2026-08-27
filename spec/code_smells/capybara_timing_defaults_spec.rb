# frozen_string_literal: true

require "rails_helper"

# Capybara's stock `default_max_wait_time` is 2 seconds. This suite runs four
# RSpec workers per CI shard — eighteen in the Lefthook pre-push run — each
# driving its own headless Chrome, and 2s loses against that contention.
#
# Nobody had set the global. The suite had instead paid for it 46 separate
# times in hand-tuned `wait:` overrides, each one a private renegotiation of a
# default nobody owned (panel audit, 2026-08-26). A `wait:` at a call site
# should mean "this operation is genuinely slower than the rest of the suite" —
# it cannot mean that while the baseline is wrong for the hardware.
#
# Pinned here so a silent revert to the stock value fails as one legible
# assertion rather than as an intermittent red shard somewhere else.
RSpec.describe "Capybara timing defaults" do
  it "sets default_max_wait_time explicitly, and higher under CI contention" do
    expect(Capybara.default_max_wait_time).to eq(ENV["CI"].present? ? 10 : 5)
  end
end
