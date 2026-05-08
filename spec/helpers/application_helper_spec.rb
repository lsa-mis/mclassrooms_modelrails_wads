require "rails_helper"

RSpec.describe ApplicationHelper do
  describe "#safe_html" do
    it "marks trusted HTML as safe so ERB output does not escape it" do
      result = helper.safe_html("<p>hi</p>")

      expect(result).to be_html_safe
      expect(result.to_s).to eq("<p>hi</p>")
    end

    it "returns nil unchanged when given nil" do
      expect(helper.safe_html(nil)).to be_nil
    end
  end
end
