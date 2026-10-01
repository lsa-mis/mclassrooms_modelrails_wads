require "rails_helper"

RSpec.describe IconRegistry do
  before { described_class.reload! }

  describe ".find" do
    it "returns parsed SVG data for a known outline icon" do
      result = described_class.find(:check_circle)
      expect(result[:inner_html]).to include("stroke-linecap")
      expect(result[:viewbox]).to eq("0 0 24 24")
      expect(result[:style]).to eq(:outline)
    end

    it "returns parsed SVG data for a known solid icon" do
      result = described_class.find(:x_mark, style: :solid)
      expect(result[:inner_html]).to include("<path")
      expect(result[:viewbox]).to eq("0 0 20 20")
      expect(result[:style]).to eq(:solid)
    end

    it "prefers outline when no style specified" do
      result = described_class.find(:x_mark)
      expect(result[:style]).to eq(:outline)
    end

    it "falls back to solid when outline not available" do
      solid_dir = Rails.root.join("app/assets/icons/solid")
      test_file = solid_dir.join("test_solid_only.svg")
      File.write(test_file, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path d="M10 10z"/></svg>')
      described_class.reload!

      result = described_class.find(:test_solid_only)
      expect(result[:style]).to eq(:solid)
    ensure
      File.delete(test_file) if test_file&.exist?
      described_class.reload!
    end

    it "raises NotFound for unknown icons" do
      expect { described_class.find(:nonexistent_icon) }.to raise_error(IconRegistry::NotFound)
    end
  end

  describe ".exists?" do
    it "returns true for known icons" do
      expect(described_class.exists?(:check_circle)).to be true
    end

    it "returns false for unknown icons" do
      expect(described_class.exists?(:nonexistent_icon)).to be false
    end

    it "checks specific style when provided" do
      expect(described_class.exists?(:x_mark, style: :solid)).to be true
      expect(described_class.exists?(:check_circle, style: :solid)).to be false
    end
  end

  describe "find and exists? consult the same styles" do
    def with_solid_only_icon
      test_file = Rails.root.join("app/assets/icons/solid/test_solid_only.svg")
      File.write(test_file, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path d="M10 10z"/></svg>')
      described_class.reload!
      yield
    ensure
      File.delete(test_file) if test_file&.exist?
      described_class.reload!
    end

    def found?(name, style)
      described_class.find(name, style: style).present?
    rescue IconRegistry::NotFound
      false
    end

    it "answer alike for every icon and style, including one that exists only in solid" do
      with_solid_only_icon do
        lookups = described_class.available_icons.product([ nil, *IconRegistry::STYLES ])

        lookups.each do |name, style|
          expect(described_class.exists?(name, style: style)).to eq(found?(name, style)), "#{name} #{style.inspect}"
        end
      end
    end
  end

  describe ".available_icons" do
    it "returns a sorted array of symbol names" do
      icons = described_class.available_icons
      expect(icons).to be_an(Array)
      expect(icons).to include(:check_circle, :x_mark, :sun, :moon)
      expect(icons).to eq(icons.sort)
    end

    it "deduplicates icons available in both styles" do
      icons = described_class.available_icons
      expect(icons.count(:x_mark)).to eq(1)
    end
  end

  describe ".reload!" do
    it "clears the cache" do
      described_class.find(:check_circle)
      described_class.reload!
      result = described_class.find(:check_circle)
      expect(result[:inner_html]).to include("stroke-linecap")
    end
  end

  describe "caching" do
    it "returns the same object on subsequent calls" do
      result1 = described_class.find(:check_circle)
      result2 = described_class.find(:check_circle)
      expect(result1).to equal(result2)
    end
  end
end
