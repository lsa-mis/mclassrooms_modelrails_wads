require "rails_helper"

RSpec.describe PasswordSignIn, type: :model do
  let(:user) { create(:user) } # factory password: "SecureP@ssw0rd123!"
  let(:right_password) { "SecureP@ssw0rd123!" }

  def attempt(email:, password:)
    described_class.new(email_address: email, password: password)
  end

  it "returns the user for the right password" do
    expect(attempt(email: user.email_address, password: right_password).user).to eq(user)
  end

  it "returns no user for a wrong password, carries the generic error, and counts the attempt" do
    sign_in = attempt(email: user.email_address, password: "wrongpassword")

    expect(sign_in.user).to be_nil
    expect(sign_in.errors.full_messages).to eq([ I18n.t("sessions.create.failure") ])
    expect(user.reload.failed_login_attempts).to eq(1)
  end

  it "gives an unknown address exactly the error a wrong password gets" do
    unknown = attempt(email: "ghost@example.com", password: "anything").tap(&:user)
    wrong = attempt(email: user.email_address, password: "wrongpassword").tap(&:user)

    expect(unknown.errors.full_messages).to eq(wrong.errors.full_messages)
  end

  it "hashes a password for an unknown address, so it takes as long as a wrong one" do
    allow(BCrypt::Password).to receive(:create).and_call_original

    attempt(email: "ghost@example.com", password: "anything").user

    expect(BCrypt::Password).to have_received(:create)
  end

  it "hashes for an account without a password too, so a passwordless account answers no faster than a missing one" do
    user.update_column(:password_digest, nil)
    allow(BCrypt::Password).to receive(:create).and_call_original

    expect(attempt(email: user.email_address, password: "anything").user).to be_nil
    expect(BCrypt::Password).to have_received(:create)
  end

  it "refuses a locked account even with the right password, with the same error, and leaves the count alone" do
    5.times { user.register_failed_login! }
    sign_in = attempt(email: user.email_address, password: right_password)

    expect(sign_in.user).to be_nil
    expect(sign_in.errors.full_messages).to eq([ I18n.t("sessions.create.failure") ])
    expect(user.reload.failed_login_attempts).to eq(5)
  end

  it "checks the password of a locked account anyway, so a lock answers no faster than a wrong password" do
    5.times { user.register_failed_login! }
    expect_any_instance_of(User).to receive(:authenticate).and_call_original

    attempt(email: user.email_address, password: "wrongpassword").user
  end

  it "does not count a blank password as an attempt" do
    sign_in = attempt(email: user.email_address, password: "")

    expect(sign_in.user).to be_nil
    expect(sign_in.errors.full_messages).to eq([ I18n.t("sessions.create.failure") ])
    expect(user.reload.failed_login_attempts).to eq(0)
  end
end
