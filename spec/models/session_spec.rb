require "rails_helper"

RSpec.describe Session, type: :model do
  describe "associations" do
    it "belongs to a user" do
      expect(Session.reflect_on_association(:user).macro).to eq(:belongs_to)
    end
  end
end
