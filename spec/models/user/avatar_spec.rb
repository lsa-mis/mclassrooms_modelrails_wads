require "rails_helper"

# User::Avatar's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe User, type: :model do
  describe "avatar_source validation" do
    it "allows 'upload' as avatar_source" do
      user = build(:user, avatar_source: "upload")
      user.valid?
      expect(user.errors[:avatar_source]).to be_empty
    end

    it "allows 'gravatar' as avatar_source" do
      user = build(:user, avatar_source: "gravatar")
      user.valid?
      expect(user.errors[:avatar_source]).to be_empty
    end

    it "allows 'initials' as avatar_source" do
      user = build(:user, avatar_source: "initials")
      user.valid?
      expect(user.errors[:avatar_source]).to be_empty
    end

    it "rejects invalid avatar_source" do
      user = build(:user, avatar_source: "invalid")
      expect(user).not_to be_valid
      expect(user.errors[:avatar_source]).to be_present
    end
  end

  describe "#gravatar_url" do
    it "generates a SHA256-based Gravatar URL" do
      user = build(:user, email_address: "test@example.com")
      hash = Digest::SHA256.hexdigest("test@example.com")
      expect(user.gravatar_url).to eq("https://www.gravatar.com/avatar/#{hash}?s=128&d=404")
    end

    it "accepts a custom size" do
      user = build(:user, email_address: "test@example.com")
      expect(user.gravatar_url(size: 64)).to include("s=64")
    end

    it "normalizes email before hashing" do
      user = build(:user, email_address: "Test@Example.COM")
      hash = Digest::SHA256.hexdigest("test@example.com")
      expect(user.gravatar_url).to include(hash)
    end

    it "returns nil when email is blank" do
      user = build(:user)
      allow(user).to receive(:email_address).and_return(nil)
      expect(user.gravatar_url).to be_nil
    end
  end

  describe "avatar_original" do
    it "supports avatar_original attachment" do
      user = create(:user)
      user.avatar_original.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "original.png",
        content_type: "image/png"
      )
      expect(user.avatar_original).to be_attached
    end
  end

  describe "avatar_original attachment" do
    it "rejects non-image content types" do
      user = create(:user)
      user.avatar_original.attach(
        io: StringIO.new("not an image"),
        filename: "doc.pdf",
        content_type: "application/pdf"
      )
      expect(user).not_to be_valid
      expect(user.errors[:avatar_original]).to be_present
    end

    it "rejects files over 10MB" do
      user = create(:user)
      user.avatar_original.attach(
        io: StringIO.new("x" * 11.megabytes),
        filename: "huge.png",
        content_type: "image/png"
      )
      expect(user).not_to be_valid
      expect(user.errors[:avatar_original]).to be_present
    end
  end

  describe "#available_avatar_sources" do
    it "always includes upload" do
      user = create(:user)
      expect(user.available_avatar_sources).to include("upload")
    end

    it "always includes initials" do
      user = create(:user)
      expect(user.available_avatar_sources).to include("initials")
    end

    it "includes gravatar when user has gravatar" do
      user = create(:user)
      user.update_columns(has_gravatar: true)
      expect(user.available_avatar_sources).to include("gravatar")
    end

    it "excludes gravatar when user has no gravatar" do
      user = create(:user)
      user.update_columns(has_gravatar: false)
      expect(user.available_avatar_sources).not_to include("gravatar")
    end
  end

  describe "avatar Active Storage validations" do
    # HEIC/HEIF included: it is the iPhone camera default, so rejecting it
    # bounces the most common source of an avatar upload. Safe to accept — the
    # active_storage initializer records that both load and transform under
    # Vips.block_untrusted(true) after CVE-2026-66066, and Rails converts the
    # variant to PNG automatically because they are not web_image_content_types.
    it "accepts valid image content types" do
      user = create(:user)
      %w[image/png image/jpeg image/gif image/webp image/heic image/heif].each do |content_type|
        user.avatar.attach(io: StringIO.new("fake"), filename: "test.png", content_type: content_type)
        user.valid?
        expect(user.errors[:avatar]).to be_empty, "Expected #{content_type} to be valid"
      end
    end

    it "rejects invalid content types" do
      user = create(:user)
      user.avatar.attach(io: StringIO.new("fake"), filename: "test.txt", content_type: "text/plain")
      expect(user).not_to be_valid
      expect(user.errors[:avatar]).to be_present
    end

    it "rejects files over 5MB" do
      user = create(:user)
      large_io = StringIO.new("x" * 6.megabytes)
      user.avatar.attach(io: large_io, filename: "big.png", content_type: "image/png")
      expect(user).not_to be_valid
      expect(user.errors[:avatar]).to be_present
    end
  end

  describe "Gravatar check callbacks" do
    it "enqueues CheckGravatarJob after create" do
      expect {
        create(:user)
      }.to have_enqueued_job(CheckGravatarJob)
    end

    it "enqueues CheckGravatarJob after email change" do
      user = create(:user)
      expect {
        user.update!(email_address: "newemail#{SecureRandom.hex(4)}@example.com")
      }.to have_enqueued_job(CheckGravatarJob)
    end

    it "does not enqueue CheckGravatarJob when email does not change" do
      user = create(:user)
      expect {
        user.update!(first_name: "Updated")
      }.not_to have_enqueued_job(CheckGravatarJob)
    end
  end

  describe "primary_color" do
    it "defaults to 210" do
      user = create(:user)
      expect(user.primary_color).to eq(210)
    end

    it "validates inclusion in 0..360" do
      user = build(:user, primary_color: 180)
      expect(user).to be_valid

      user.primary_color = -1
      expect(user).not_to be_valid

      user.primary_color = 361
      expect(user).not_to be_valid
    end

    it "allows nil" do
      user = build(:user, primary_color: nil)
      expect(user).to be_valid
    end
  end
end
