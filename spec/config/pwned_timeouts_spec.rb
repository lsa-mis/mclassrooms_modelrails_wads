require "rails_helper"

# #674 defense in depth: without explicit timeouts, a pwnedpasswords.com
# outage rides Net::HTTP's defaults (60s open + 60s read) — and anywhere the
# check runs inside a write transaction that becomes an app-wide write stall
# on SQLite's database-wide lock. Bounded here regardless of call site.
RSpec.describe "Pwned request timeouts" do
  it "bounds the HIBP range request to seconds, not Net::HTTP defaults" do
    expect(Pwned.default_request_options).to include(open_timeout: 1, read_timeout: 2)
  end
end
