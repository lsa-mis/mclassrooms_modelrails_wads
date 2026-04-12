require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    it "requires an email address" do
      user = User.new(email_address: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to be_present
    end

    it "requires a unique email address" do
      create(:user, email_address: "test@example.com")
      duplicate = build(:user, email_address: "test@example.com")
      expect(duplicate).not_to be_valid
    end

    it "normalizes email to lowercase" do
      user = create(:user, email_address: "Test@Example.COM")
      expect(user.email_address).to eq("test@example.com")
    end
  end

  describe "associations" do
    it "has many sessions" do
      user = create(:user)
      session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      expect(user.sessions).to include(session)
    end
  end

  describe "personal workspace" do
    it "creates a personal workspace on sign-up" do
      user = create(:user)
      expect(user.workspaces.count).to eq(1)
      expect(user.workspaces.first.name).to include(user.first_name)
    end

    it "assigns owner role to personal workspace" do
      user = create(:user)
      membership = user.memberships.first
      expect(membership.role.slug).to eq("owner")
    end
  end

  describe "#full_name" do
    it "returns first and last name" do
      user = build(:user, first_name: "Jane", last_name: "Doe")
      expect(user.full_name).to eq("Jane Doe")
    end
  end

  describe "#initials" do
    it "returns first letters of first and last name" do
      user = build(:user, first_name: "Jane", last_name: "Doe")
      expect(user.initials).to eq("JD")
    end

    it "returns single initial when only first name" do
      user = build(:user, first_name: "Jane", last_name: "")
      expect(user.initials).to eq("J")
    end

    it "returns fallback when name is blank" do
      user = build(:user, first_name: "", last_name: "")
      expect(user.initials).to eq("?")
    end
  end

  describe "name validations" do
    it "requires first_name" do
      user = build(:user, first_name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:first_name]).to be_present
    end

    it "limits first_name to 100 characters" do
      user = build(:user, first_name: "a" * 101)
      expect(user).not_to be_valid
      expect(user.errors[:first_name]).to be_present
    end

    it "requires last_name" do
      user = build(:user, last_name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:last_name]).to be_present
    end

    it "limits last_name to 100 characters" do
      user = build(:user, last_name: "a" * 101)
      expect(user).not_to be_valid
      expect(user.errors[:last_name]).to be_present
    end
  end

  describe "password validations" do
    it "requires minimum 12 characters" do
      user = build(:user, password: "Short1!aaa")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "accepts 12+ character password" do
      user = build(:user, password: "ValidP@ssw0rd!")
      expect(user).to be_valid
    end
  end

  describe "Pwned API failure resilience" do
    it "allows registration when Pwned API raises an error" do
      pwned = instance_double(Pwned::Password)
      allow(pwned).to receive(:pwned?).and_raise(Pwned::Error.new("timeout"))
      allow(Pwned::Password).to receive(:new).and_return(pwned)

      user = build(:user, password: "SecureP@ssw0rd123!")
      expect(user).to be_valid
    end
  end

  describe "email normalization" do
    it "strips whitespace from email" do
      user = create(:user, email_address: "  test@example.com  ")
      expect(user.email_address).to eq("test@example.com")
    end
  end

  describe "account locking" do
    let(:user) { create(:user) }

    it "locks after 5 failed attempts" do
      5.times { user.register_failed_login! }
      expect(user.reload).to be_locked
    end

    it "does not lock after 4 failed attempts" do
      4.times { user.register_failed_login! }
      expect(user.reload).not_to be_locked
    end

    it "auto-unlocks after 1 hour" do
      user.update!(locked_at: 61.minutes.ago, failed_login_attempts: 5)
      expect(user).not_to be_locked
    end

    it "resets failed attempts on successful login" do
      3.times { user.register_failed_login! }
      user.register_successful_login!
      expect(user.reload.failed_login_attempts).to eq(0)
    end
  end

  describe "#initiate_email_change!" do
    let(:user) { create(:user) }

    it "sets pending fields when password is correct" do
      result = user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
      expect(result).to be true
      expect(user.reload.pending_email).to eq("new@example.com")
      expect(user.pending_email_token).to be_present
      expect(user.pending_email_sent_at).to be_present
    end

    it "returns false when password is wrong" do
      result = user.initiate_email_change!("new@example.com", "wrongpassword")
      expect(result).to be false
      expect(user.reload.pending_email).to be_nil
    end

    it "returns false when email format is invalid" do
      result = user.initiate_email_change!("notanemail", "SecureP@ssw0rd123!")
      expect(result).to be false
      expect(user.reload.pending_email).to be_nil
    end

    it "returns false when email is already taken" do
      create(:user, email_address: "taken@example.com")
      result = user.initiate_email_change!("taken@example.com", "SecureP@ssw0rd123!")
      expect(result).to be false
      expect(user.reload.pending_email).to be_nil
    end

    it "returns false when email is same as current" do
      result = user.initiate_email_change!(user.email_address, "SecureP@ssw0rd123!")
      expect(result).to be false
    end

    it "overwrites previous pending change" do
      user.initiate_email_change!("first@example.com", "SecureP@ssw0rd123!")
      user.initiate_email_change!("second@example.com", "SecureP@ssw0rd123!")
      expect(user.reload.pending_email).to eq("second@example.com")
    end

    it "returns false for passwordless user" do
      oauth_user = create(:user, password: nil, password_digest: nil)
      result = oauth_user.initiate_email_change!("new@example.com", "anything")
      expect(result).to be false
    end

    it "normalizes the pending email" do
      user.initiate_email_change!("  NEW@EXAMPLE.COM  ", "SecureP@ssw0rd123!")
      expect(user.reload.pending_email).to eq("new@example.com")
    end
  end

  describe "#confirm_email_change!" do
    let(:user) { create(:user, :with_email_auth) }

    before do
      user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
      user.reload
    end

    it "updates email_address with valid token" do
      token = user.pending_email_token
      result = user.confirm_email_change!(token)
      expect(result).to be true
      expect(user.reload.email_address).to eq("new@example.com")
    end

    it "updates email Authentication uid" do
      email_auth = user.authentications.email.first
      token = user.pending_email_token
      user.confirm_email_change!(token)
      expect(email_auth.reload.uid).to eq("new@example.com")
    end

    it "does not touch OAuth authentications" do
      oauth_auth = user.authentications.create!(provider: "google", uid: "google123", verified_at: Time.current)
      token = user.pending_email_token
      user.confirm_email_change!(token)
      expect(oauth_auth.reload.uid).to eq("google123")
    end

    it "clears pending fields" do
      token = user.pending_email_token
      user.confirm_email_change!(token)
      user.reload
      expect(user.pending_email).to be_nil
      expect(user.pending_email_token).to be_nil
      expect(user.pending_email_sent_at).to be_nil
    end

    it "returns false for expired token" do
      user.update!(pending_email_sent_at: 25.hours.ago)
      result = user.confirm_email_change!(user.pending_email_token)
      expect(result).to be false
      expect(user.reload.email_address).not_to eq("new@example.com")
    end

    it "returns false for wrong token" do
      result = user.confirm_email_change!("wrong-token")
      expect(result).to be false
    end

    it "returns false for nil token" do
      result = user.confirm_email_change!(nil)
      expect(result).to be false
    end
  end

  describe "#cancel_email_change!" do
    let(:user) { create(:user) }

    it "clears all pending fields" do
      user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
      user.cancel_email_change!
      user.reload
      expect(user.pending_email).to be_nil
      expect(user.pending_email_token).to be_nil
      expect(user.pending_email_sent_at).to be_nil
    end
  end

  describe "#pending_email_token_valid?" do
    let(:user) { create(:user) }

    it "returns true for fresh token" do
      user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
      expect(user.pending_email_token_valid?).to be true
    end

    it "returns false for expired token" do
      user.initiate_email_change!("new@example.com", "SecureP@ssw0rd123!")
      user.update!(pending_email_sent_at: 25.hours.ago)
      expect(user.pending_email_token_valid?).to be false
    end

    it "returns false when no token" do
      expect(user.pending_email_token_valid?).to be false
    end
  end

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
    it "accepts valid image content types" do
      user = create(:user)
      %w[image/png image/jpeg image/gif image/webp].each do |content_type|
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
