require "rails_helper"

RSpec.describe EmailLookup, type: :model do
  describe "#valid?" do
    it "is valid with a properly-formatted email" do
      form = described_class.new(email_address: "alice@example.com")
      expect(form).to be_valid
    end

    it "is invalid when email_address is blank" do
      form = described_class.new(email_address: "")
      expect(form).not_to be_valid
      expect(form.errors[:email_address]).to include(I18n.t("sessions.lookups.create.invalid_email"))
    end

    it "is invalid when email_address is nil" do
      form = described_class.new(email_address: nil)
      expect(form).not_to be_valid
      expect(form.errors[:email_address]).to include(I18n.t("sessions.lookups.create.invalid_email"))
    end

    it "is invalid when email_address has no domain TLD" do
      form = described_class.new(email_address: "alice@example")
      expect(form).not_to be_valid
      expect(form.errors[:email_address]).to include(I18n.t("sessions.lookups.create.invalid_email"))
    end

    it "is invalid when email_address has no @ separator" do
      form = described_class.new(email_address: "notanemail")
      expect(form).not_to be_valid
      expect(form.errors[:email_address]).to include(I18n.t("sessions.lookups.create.invalid_email"))
    end

    it "uses the same user-facing error message for blank, nil, and malformed inputs" do
      # Pin the unified-message contract so a future divergence (e.g., default
      # 'can't be blank' creeping back in for the presence case) gets caught.
      messages = [ "", nil, "no-at-sign", "missing-tld@example" ].map do |bad|
        form = described_class.new(email_address: bad)
        form.valid?
        form.errors[:email_address].first
      end
      expect(messages).to all(eq(I18n.t("sessions.lookups.create.invalid_email")))
    end
  end

  describe "ActiveModel integration (form-builder compatibility)" do
    it "responds to errors for TailwindFormBuilder.has_errors? lookup" do
      form = described_class.new(email_address: "")
      form.valid?
      expect(form.errors[:email_address].any?).to be true
    end

    it "exposes email_address as an attribute readable by form helpers" do
      form = described_class.new(email_address: "alice@example.com")
      expect(form.email_address).to eq("alice@example.com")
    end
  end
end
