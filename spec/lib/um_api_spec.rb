require "rails_helper"

# UmApi.fiscal_year — Task 8 of planning/plans/phase-2-ingestion.md.
# Sync::UpdateBuildings fetches buildings scoped to "the current fiscal
# year" (Brief §6.1), and U-M's fiscal year runs July 1 -> June 30, so a
# calendar date in the second half of the year (July-December) belongs to
# NEXT calendar year's fiscal year, while January-June belongs to the
# current one. This is pinned as its own unit so Sync::UpdateBuildings can
# treat it as a one-line query-param input without re-deriving the July
# cutover itself.
RSpec.describe UmApi do
  describe ".fiscal_year" do
    it "rolls over to next year on July 1st (the FY start)" do
      expect(UmApi.fiscal_year(Date.new(2026, 7, 1))).to eq(2027)
    end

    it "stays in next year's FY through December 31st" do
      expect(UmApi.fiscal_year(Date.new(2026, 12, 31))).to eq(2027)
    end

    it "is still the current year on June 30th (the day before rollover)" do
      expect(UmApi.fiscal_year(Date.new(2026, 6, 30))).to eq(2026)
    end

    it "is the current year in January" do
      expect(UmApi.fiscal_year(Date.new(2026, 1, 1))).to eq(2026)
    end
  end
end
