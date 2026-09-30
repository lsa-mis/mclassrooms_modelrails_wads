require "rails_helper"

RSpec.describe FloorLabel do
  it "strips leading zeros without collapsing a label to nothing" do
    expect(%w[01 0G 00 2 B 10].map { |raw| described_class.normalize(raw) }).to eq(%w[1 G 0 2 B 10])
  end

  it "trims whitespace and tolerates nil" do
    expect(described_class.normalize(" 03 ")).to eq("3")
    expect(described_class.normalize(nil)).to eq("")
  end
end
