class User < ApplicationRecord
  # The optional password credential: its validations, lockout, removal, and the
  # audit and notice every digest change produces.
  # See /docs/developer/accounts-and-identity (Password lifecycle).
  module Password
    extend ActiveSupport::Concern

    MAX_FAILED_ATTEMPTS = 5
    LOCK_DURATION = 1.hour

    included do
      has_secure_password validations: false

      validates :password, length: { minimum: 12 }, if: -> { password.present? && (password_digest_changed? || new_record?) }
      validates :password, confirmation: true, if: -> { password.present? }
      validate :password_not_pwned, if: -> { password.present? && (password_digest_changed? || new_record?) }

      # Model-level so every digest-touching path notifies (settings change, reset,
      # removal) — the behavior app/docs/developer/notifications.md documents.
      after_update_commit :notify_password_changed, if: :saved_change_to_password_digest?
      # Strict tier: after_update, not _commit, so the audit row commits with the credential write.
      # See /docs/developer/architecture (Activity Tracking).
      after_update :audit_password_digest_change, if: :saved_change_to_password_digest?
    end

    def locked?
      return false if locked_at.nil?
      locked_at > LOCK_DURATION.ago
    end

    # An expired lock starts the count over: nothing else clears the counter
    # when the hour passes, so the stale count would re-lock on the next miss.
    def register_failed_login!
      update!(failed_login_attempts: 0, locked_at: nil) if locked_at.present? && !locked?
      increment!(:failed_login_attempts)
      update!(locked_at: Time.current) if failed_login_attempts >= MAX_FAILED_ATTEMPTS
    end

    # Clears the same two columns unlock! does, but writes no audit row: the
    # Session row created moments later is already this event's record. The
    # operator path below needs its own row because nothing else marks that
    # an operator, not a login, ended the lockout.
    def register_successful_login!
      update!(failed_login_attempts: 0, locked_at: nil)
    end

    # The operator control (Operations::Users::LocksController). Guards on
    # locked_at.nil?, not locked?: an EXPIRED lock still carries a stale
    # failed-attempt counter, and "let them try again" should clear it too.
    # STRICT audit, like the suspension pair in User::Suspension.
    def unlock!(by:)
      transaction do
        lock!
        next :not_locked if locked_at.nil?
        update!(failed_login_attempts: 0, locked_at: nil)
        ActivityLog.record_security_event!(action: "user.unlocked", user: self, actor: by, visibility: "admin")
        :unlocked
      end
    end

    # The reload is the idempotence guard (#826): a stale digest would otherwise write a second audit row.
    # See /docs/developer/accounts-and-identity (Password lifecycle).
    def remove_password!
      transaction do
        reload
        next false if password_digest.nil?

        authentications.email.destroy_all
        # save!(validate: false): an unrelated validation failure must not block removal; callbacks still run (#820).
        self.password_digest = nil
        save!(validate: false)
        yield if block_given?
        true
      end
    end

    def has_password?
      password_digest.present?
    end

    # Call between assign_attributes and save: the HIBP check must not run inside BEGIN IMMEDIATE (#674).
    # See /docs/developer/architecture (Concurrency).
    def precheck_password_pwned!
      return if password.blank?
      @pwned_precheck = [ password, password_pwned_now? ]
      nil
    end

    private

    def audit_password_digest_change
      ActivityLog.record_security_event!(
        action: password_digest.nil? ? "user.password_removed" : "user.password_changed",
        user: self
      )
    end

    # Best-effort: the security alert must never fail the credential write
    # itself (same contract as the new-device hook in Authenticatable).
    def notify_password_changed
      PasswordChangedNotifier.with(record: self, removed: password_digest.nil?).deliver(self)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[password-changed] swallowed error for user=#{id}: #{e.class}: #{e.message}")
    end

    def password_not_pwned
      return if password.blank?
      pwned =
        if @pwned_precheck && @pwned_precheck[0] == password
          @pwned_precheck[1]
        else
          password_pwned_now?
        end
      errors.add(:password, :pwned) if pwned
    end

    def password_pwned_now?
      Pwned::Password.new(password).pwned?
    rescue Pwned::Error
      # Network error — allow password (don't block registration on external service failure)
      false
    end
  end
end
