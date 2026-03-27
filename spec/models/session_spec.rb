require "rails_helper"

RSpec.describe Session, type: :model do
  describe "associations" do
    it "belongs to a user" do
      user = create(:user)
      session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      expect(session.user).to eq(user)
    end
  end
end
