require "rails_helper"

RSpec.describe WorkspaceIdentity do
  let(:workspace) { create(:workspace, name: "Acme Rockets") }
  let(:identity) { workspace.identity }
  let(:identity_with_image) { create(:workspace, :with_logo).identity }
  let(:expected_initials) { "AR" }

  it_behaves_like "an identity read surface"

  it "is returned by Workspace#identity" do
    expect(workspace.identity).to be_a(described_class)
  end

  describe "attribute mapping" do
    it "maps image/source to the logo attributes" do
      expect(identity_with_image.image).to be_attached
      expect(identity_with_image.source).to eq("upload")
    end
  end

  describe "#gravatar_url" do
    it "is always nil — workspaces have no email address" do
      expect(identity.gravatar_url).to be_nil
      expect(identity.gravatar_url(size: 64)).to be_nil
    end
  end

  describe "#available_sources" do
    it "returns upload and initials" do
      expect(identity.available_sources).to eq(%w[upload initials])
    end
  end
end
