require "rails_helper"

RSpec.describe Current, type: :model do
  describe "attributes" do
    it "has session attribute" do
      expect(Current).to respond_to(:session)
    end

    it "has workspace attribute" do
      expect(Current).to respond_to(:workspace)
    end
  end

  describe ".workspace!" do
    it "returns the workspace when context is established" do
      workspace = create(:workspace)
      Current.workspace = workspace
      expect(Current.workspace!).to eq(workspace)
    end

    it "raises NoWorkspaceError when context was never established" do
      Current.workspace = nil
      expect { Current.workspace! }.to raise_error(
        Current::NoWorkspaceError, /establish workspace context/
      )
    end
  end

  describe "delegation" do
    it "delegates user to session" do
      user = create(:user)
      session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      Current.session = session
      expect(Current.user).to eq(user)
    end

    it "returns nil for user when session is nil" do
      Current.session = nil
      expect(Current.user).to be_nil
    end
  end
end
