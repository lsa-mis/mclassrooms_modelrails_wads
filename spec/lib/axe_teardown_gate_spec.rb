# frozen_string_literal: true

require "rails_helper"

# The after(:suite) gate in spec/support/axe_accessibility.rb decides from two
# ledgers which system examples navigated without being audited (#912). The
# decision is a pure function, so it is pinned here without a browser.
RSpec.describe AxeAccessibility, ".unaudited" do
  it "flags an example that navigated and has no :audited entry, whatever else the ledger says" do
    ledger  = { "a" => :audited, "b" => :blank, "c" => :blank }
    visited = Set["a", "b", "d"]

    expect(described_class.unaudited(%w[a b c d], ledger: ledger, visited: visited)).to eq(%w[b d])
  end

  it "flags an example the hook never touched, even one that never navigated" do
    expect(described_class.unaudited(%w[x], ledger: {}, visited: Set.new)).to eq(%w[x])
  end
end
