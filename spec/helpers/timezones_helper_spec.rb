require "rails_helper"

# Helper that builds the structured option list for the timezone picker
# on the preferences page. Native <select> with optgroups via
# grouped_options_for_select — zero JS, AAA-by-default through optgroup
# announcements, browser type-to-jump works out of the box.
#
# The list is shaped as [["GroupLabel", [zone1, zone2, ...]], ...]. The
# first group is unlabeled and contains the 10 common US zones; the
# remaining groups are regional (Americas, Europe, Asia, Pacific,
# Africa, Atlantic, Indian).
RSpec.describe TimezonesHelper, type: :helper do
  describe "#timezone_options_for_select" do
    let(:options) { helper.timezone_options_for_select }

    it "returns an array of [group_label, [iana_names]] tuples" do
      expect(options).to be_an(Array)
      options.each do |group_label, names|
        expect(group_label).to be_a(String)
        expect(names).to be_an(Array)
        expect(names).to all(be_a(String))
      end
    end

    it "places the 10 common US zones in the first group, unlabeled" do
      first_label, first_zones = options.first
      expect(first_label).to eq("")
      expect(first_zones.size).to eq(10)
      expect(first_zones).to include(
        "America/New_York",
        "America/Chicago",
        "America/Denver",
        "America/Phoenix",
        "America/Los_Angeles",
        "America/Anchorage",
        "Pacific/Honolulu"
      )
    end

    it "includes the seven regional groups after the common group" do
      group_labels = options.map(&:first)
      expect(group_labels).to eq([
        "",
        "Americas",
        "Europe",
        "Asia",
        "Pacific",
        "Africa",
        "Atlantic",
        "Indian"
      ])
    end

    it "lists non-common Americas zones (Toronto, São Paulo) under Americas" do
      americas = options.find { |label, _| label == "Americas" }.last
      expect(americas).to include("America/Toronto")
      expect(americas).to include("America/Sao_Paulo")
    end

    it "excludes the 10 common US zones from the Americas group (no duplicates)" do
      americas = options.find { |label, _| label == "Americas" }.last
      common_us = options.first.last
      expect(americas & common_us).to be_empty
    end

    it "lists Europe/London under Europe" do
      europe = options.find { |label, _| label == "Europe" }.last
      expect(europe).to include("Europe/London")
    end

    it "sorts each regional group alphabetically" do
      options.drop(1).each do |_label, names|
        expect(names).to eq(names.sort)
      end
    end
  end
end
