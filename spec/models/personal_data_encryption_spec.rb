require "rails_helper"

# Personal data is encrypted at rest (playbook standard adopted 2026-08-30;
# base #902). Deterministic only where a finder or a unique index names the
# column; every other column takes the stronger non-deterministic cipher.
# The attribute reader decrypts and so cannot tell plaintext from
# ciphertext — these examples read the column bytes through ciphertext_for.
RSpec.describe "personal data at rest" do
  def envelope?(column_bytes)
    column_bytes.is_a?(String) && column_bytes.start_with?('{"p":')
  end

  describe User do
    it "stores email_address as ciphertext and still finds it by a case variant" do
      user = create(:user, email_address: "ada@example.com")

      expect(envelope?(user.ciphertext_for(:email_address))).to be(true)
      expect(User.find_by(email_address: "ADA@Example.com")).to eq(user)
    end

    it "normalizes before it encrypts" do
      expect(User.new(email_address: " Ada@Example.com ").email_address).to eq("ada@example.com")
    end

    it "keeps email_address unique at the database, on ciphertext" do
      create(:user, email_address: "ada@example.com")
      twin = build(:user, :no_authentications, email_address: "Ada@Example.com")

      expect(twin).not_to be_valid
      expect { twin.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "stores names and the pending email as ciphertext, non-deterministically" do
      ada = create(:user, first_name: "Ada", pending_email: "next@example.com")
      other_ada = create(:user, first_name: "Ada")

      expect(envelope?(ada.ciphertext_for(:first_name))).to be(true)
      expect(envelope?(ada.ciphertext_for(:last_name))).to be(true)
      expect(envelope?(ada.ciphertext_for(:pending_email))).to be(true)
      expect(ada.ciphertext_for(:first_name)).not_to eq(other_ada.ciphertext_for(:first_name))
    end
  end

  describe Authentication do
    it "stores uid as ciphertext and still finds the row by provider and uid" do
      auth = create(:authentication, :google)

      expect(envelope?(auth.ciphertext_for(:uid))).to be(true)
      expect(Authentication.find_by(provider: "google", uid: auth.uid)).to eq(auth)
    end

    it "stores the provider-supplied email as ciphertext" do
      auth = create(:authentication, :google, email: "ada@home.example")

      expect(envelope?(auth.ciphertext_for(:email))).to be(true)
      expect(auth.reload.email).to eq("ada@home.example")
    end

    it "keeps (provider, uid) unique at the database, on ciphertext" do
      auth = create(:authentication, :google)
      twin = build(:authentication, :google, uid: auth.uid)

      expect(twin).not_to be_valid
      expect { twin.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe Invitation do
    let(:workspace) { create(:workspace) }

    it "stores email as ciphertext, deterministic so the pending-invite index still enforces" do
      invitation = create(:invitation, invitable: workspace, email: "ada@example.com")
      twin = build(:invitation, invitable: workspace, email: "ADA@Example.com")

      expect(envelope?(invitation.ciphertext_for(:email))).to be(true)
      expect { twin.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe MagicLinkToken do
    it "stores email as ciphertext, deterministic so one unconsumed token per address still holds" do
      first = MagicLinkToken.create_for_email("ada@example.com")

      expect(envelope?(MagicLinkToken.find_valid(first).ciphertext_for(:email))).to be(true)

      MagicLinkToken.create_for_email("ADA@Example.com")
      expect(MagicLinkToken.find_valid(first)).to be_nil
    end
  end

  describe Workspace do
    # Deliberately plaintext (#902, ruling R3): the slug is the name,
    # parameterized, and sits in every URL. Encrypting the name beside it
    # would be a comment, not a control.
    it "keeps name in plaintext" do
      workspace = create(:workspace, name: "Acme Co")

      expect(workspace.ciphertext_for(:name)).to eq("Acme Co")
    end
  end
end
