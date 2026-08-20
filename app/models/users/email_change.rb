module Users
  # The email-change state machine, extracted off User (DES-1): initiate a
  # change, confirm it with the emailed token, or cancel it. The pending state
  # (pending_email / pending_email_token / pending_email_sent_at) and its
  # validations stay on the User record; this object owns the transitions.
  class EmailChange
    TOKEN_TTL = 24.hours

    def initialize(user)
      @user = user
    end

    # Begin a change to new_email. A no-op (false) when it matches the current
    # address. Re-authentication is enforced by the controller, not here — so
    # passwordless users can change their email too (SEC-2b).
    def initiate!(new_email)
      return false if EmailNormalizer.equivalent?(EmailNormalizer.normalize(new_email), @user.email_address)

      @user.pending_email = new_email
      @user.pending_email_token = SecureRandom.urlsafe_base64(32)
      @user.pending_email_sent_at = Time.current
      @user.save
    end

    # Swap the address once the user proves ownership of the new one by clicking
    # the emailed link. Returns false (no change) on a blank/wrong/expired token
    # or a validation failure.
    def confirm!(token)
      # Guard clauses stay OUTSIDE the transaction: a `return` inside
      # `transaction do` commits rather than rolls back under modern Rails,
      # so an early exit must never share a block with the writes.
      return false if token.blank?

      @user.reload
      return false if @user.pending_email_token != token
      return false unless valid_token?

      @user.transaction do
        @user.email_address = @user.pending_email
        clear_fields
        @user.save!

        @user.authentications.email.update_all(uid: @user.email_address)
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def cancel!
      clear_fields
      @user.save!
    end

    def valid_token?
      @user.pending_email_token.present? &&
        @user.pending_email_sent_at.present? &&
        @user.pending_email_sent_at > TOKEN_TTL.ago
    end

    private

    def clear_fields
      @user.pending_email = nil
      @user.pending_email_token = nil
      @user.pending_email_sent_at = nil
    end
  end
end
