require "rails_helper"

RSpec.describe LegacyImport::Account do
  it "creates the Legacy import user once, then finds it" do
    first = nil
    expect { first = described_class.resolve(dry_run: false) }.to change(User, :count).by(1)

    expect(first).to be_persisted
    expect(first).to have_attributes(email_address: described_class::EMAIL, first_name: "Legacy", last_name: "import")
    expect { expect(described_class.resolve(dry_run: false)).to eq(first) }.not_to change(User, :count)
  end

  it "has no password and no sign-in identity" do
    user = described_class.resolve(dry_run: false)

    expect(user.password_digest).to be_nil
    expect(user.authentications).to be_empty
  end

  it "returns an unsaved stand-in on dry run" do
    user = nil
    expect { user = described_class.resolve(dry_run: true) }.not_to change(User, :count)

    expect(user).to be_new_record
  end
end
