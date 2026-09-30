require "rails_helper"

RSpec.describe LegacyImport::Tally do
  it "counts outcomes and keeps the report lines" do
    tally = described_class.new
    tally.count(:created)
    tally.count(:skipped, 2)
    tally.unmatched!("Room\t1")
    tally.replaced!("Room\t2")
    tally.error!("Room\t3\tbad")
    tally.info_lines << "gallery positions: 1 from filenames, 0 from slots"

    result = tally.to_result

    expect(result).to be_success
    expect(result.payload[:counters]).to eq(created: 1, updated: 0, replaced: 1, skipped: 2, unmatched: 1, errors: 1)
    expect(result.payload.values_at(:unmatched_lines, :replaced_lines, :error_lines, :info_lines))
      .to eq([ [ "Room\t1" ], [ "Room\t2" ], [ "Room\t3\tbad" ], [ "gallery positions: 1 from filenames, 0 from slots" ] ])
  end

  it "rejects an outcome it does not know" do
    expect { described_class.new.count(:made_up) }.to raise_error(KeyError)
  end
end
