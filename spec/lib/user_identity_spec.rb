require "rails_helper"

RSpec.describe UserIdentity do
  let(:user) { create(:user, first_name: "Ada", last_name: "Lovelace", primary_color: nil) }
  let(:identity) { user.identity }
  let(:identity_with_image) { create(:user, :with_avatar).identity }
  let(:expected_initials) { "AL" }

  it_behaves_like "an identity read surface"

  it "is returned by User#identity" do
    expect(user.identity).to be_a(described_class)
  end

  describe "attribute mapping" do
    it "maps image/image_original/source to the avatar attributes" do
      with_image = identity_with_image
      expect(with_image.image).to eq(with_image.send(:model).avatar)
      expect(with_image.source).to eq("upload")
    end
  end

  describe "#hue" do
    it "returns primary_color when set" do
      user.update!(primary_color: 270)
      expect(user.identity.hue).to eq(270)
    end
  end

  describe "#gravatar_url" do
    it "returns nil when gravatar is not an available source (never contradicts available_sources)" do
      user.update_columns(has_gravatar: false)
      expect(user.identity.gravatar_url).to be_nil
    end

    it "delegates with the requested size when gravatar is available" do
      gravatar_user = create(:user, :with_gravatar)
      expect(gravatar_user.identity.available_sources).to include("gravatar")
      expect(gravatar_user.identity.gravatar_url(size: 64)).to include("s=64")
    end

    it "defaults to size 256" do
      gravatar_user = create(:user, :with_gravatar)
      expect(gravatar_user.identity.gravatar_url).to include("s=256")
    end
  end

  describe "#available_sources" do
    it "returns upload and initials without gravatar" do
      expect(identity.available_sources).to eq(%w[upload initials])
    end
  end
end
