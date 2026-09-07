require "rails_helper"

# User::Password's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe User, type: :model do
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

  # #674: the range check is network I/O; run via precheck it happens OUTSIDE
  # the write transaction and the validation consumes the memo instead of
  # calling out again from inside BEGIN IMMEDIATE.
  describe "#precheck_password_pwned!" do
    let(:pwned) { instance_double(Pwned::Password) }

    before { allow(Pwned::Password).to receive(:new).and_return(pwned) }

    it "memoizes the result so validation does no second network call" do
      allow(pwned).to receive(:pwned?).and_return(true)
      user = build(:user, password: "SecureP@ssw0rd123!")
      user.precheck_password_pwned!

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
      expect(pwned).to have_received(:pwned?).once
    end

    it "re-checks live when the password changes after the precheck (no stale memo)" do
      allow(pwned).to receive(:pwned?).and_return(true, false)
      user = build(:user, password: "SecureP@ssw0rd123!")
      user.precheck_password_pwned!
      user.password = user.password_confirmation = "Different@Passw0rd!"

      expect(user).to be_valid
      expect(pwned).to have_received(:pwned?).twice
    end

    it "fails open when the precheck hits a Pwned::Error" do
      allow(pwned).to receive(:pwned?).and_raise(Pwned::Error.new("timeout"))
      user = build(:user, password: "SecureP@ssw0rd123!")
      user.precheck_password_pwned!

      expect(user).to be_valid
      expect(pwned).to have_received(:pwned?).once
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

  describe "password digest audit trail" do
    let(:user) { create(:user, password: "0riginal-Passw0rd!") }

    it "writes user.password_changed in the same transaction as the digest write" do
      expect {
        user.update!(password: "n3w-Sekure-Passw0rd!")
      }.to change { ActivityLog.where(action: "user.password_changed", trackable: user, visibility: "personal").count }.by(1)
    end

    it "writes user.password_removed when the digest is cleared" do
      expect {
        user.update!(password_digest: nil)
      }.to change { ActivityLog.where(action: "user.password_removed", trackable: user).count }.by(1)
    end

    it "writes exactly one user.password_changed row on the first password set (passwordless -> password)" do
      passwordless_user = create(:user, password: nil)
      expect {
        passwordless_user.update!(password: "First-Setup-Pass1!")
      }.to change {
        ActivityLog.where(action: "user.password_changed", trackable: passwordless_user, visibility: "personal").count
      }.by(1)
    end

    it "rolls back the credential write when the audit write fails (strict tier)" do
      # Ruling R7: materialize `user` BEFORE installing the stub. If the stub
      # were live already, the lazy `let(:user)` would create the user under
      # it — onboard_workspace drives audit writes through other paths, and
      # this example would pass for the wrong reason instead of proving the
      # rollback.
      original_digest = user.password_digest
      allow(ActivityLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect { user.update!(password: "n3w-Sekure-Passw0rd!") }.to raise_error(ActiveRecord::StatementInvalid)
      expect(user.reload.password_digest).to eq(original_digest)
    end

    # The controller-level guard for the concurrent double-submit: a second
    # request holding a stale in-memory digest would otherwise issue its own
    # UPDATE, satisfy saved_change_to_password_digest?, and write a second
    # removal row (#826). remove_password! re-reads inside the transaction,
    # where the write lock is already held, so the read is current.
    it "writes one removal row when two separately-loaded instances both remove" do
      user # Ruling R7: materialize before the count block.
      first = User.find(user.id)
      second = User.find(user.id)

      expect {
        first.remove_password!
        second.remove_password!
      }.to change { ActivityLog.where(action: "user.password_removed").count }.by(1)
    end

    it "reports whether it won the removal" do
      user
      first = User.find(user.id)
      second = User.find(user.id)

      expect(first.remove_password!).to be(true)
      expect(second.remove_password!).to be(false)
    end

    it "runs the caller's block inside the same transaction as the removal" do
      user
      observed = nil
      user.remove_password! { observed = User.find(user.id).password_digest }

      # The block sees the cleared digest, so it is inside the transaction
      # rather than after it — which is what keeps session revocation atomic
      # with the credential teardown.
      expect(observed).to be_nil
    end
  end
end
