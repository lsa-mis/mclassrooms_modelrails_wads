# frozen_string_literal: true

require "rails_helper"

# The floor is a whole-suite number (standards: testing/tdd-workflow, Coverage Goals; #1315).
RSpec.describe CoverageConfig do
  describe ".floor_for" do
    let(:suite) { %w[spec/a_spec.rb spec/lib/b_spec.rb spec/system/c_spec.rb] }

    it "keeps the floor when the run is every spec file" do
      expect(described_class.floor_for(suite, suite)).to eq(described_class::MINIMUM)
    end

    it "keeps the floor however the files are listed" do
      expect(described_class.floor_for(suite.reverse.map { |f| File.expand_path(f) }, suite)).to eq(described_class::MINIMUM)
    end

    it "drops the floor for a focused run" do
      expect(described_class.floor_for(suite.first(2), suite)).to eq(0)
    end
  end
end
