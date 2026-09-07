# frozen_string_literal: true

# #953: invitations.token and authentications.pending_invitation_token were
# plaintext. Reading a plaintext row through an encrypted attribute raises in
# this app (support_unencrypted_data is off), so the rows are read raw through
# shadow models and rewritten with the ciphertext the models' own attribute
# types produce. Re-runnable: rows that already decrypt are skipped.
class EncryptInvitationTokensAtRest < ActiveRecord::Migration[8.1]
  class RawInvitation < ActiveRecord::Base
    self.table_name = "invitations"
  end

  class RawAuthentication < ActiveRecord::Base
    self.table_name = "authentications"
  end

  def up
    # Fix round 1, item 6: with support_unencrypted_data on, a plaintext value
    # deserializes without raising (Rails returns it as-is), so `decrypts?`
    # below would misread every never-migrated row as already-encrypted and
    # silently skip it — a green migration that leaves tokens in the clear.
    if ActiveRecord::Encryption.config.support_unencrypted_data
      raise "support_unencrypted_data must be off: plaintext rows would be skipped as already-encrypted"
    end

    rewrite(RawInvitation, :token, Invitation.type_for_attribute("token")) { |type, value| type.serialize(value) }
    rewrite(RawAuthentication, :pending_invitation_token,
            Authentication.type_for_attribute("pending_invitation_token")) { |type, value| type.serialize(value) }
  end

  def down
    rewrite(RawInvitation, :token, Invitation.type_for_attribute("token"), encrypted_only: true) { |type, value| type.deserialize(value) }
    rewrite(RawAuthentication, :pending_invitation_token,
            Authentication.type_for_attribute("pending_invitation_token"), encrypted_only: true) { |type, value| type.deserialize(value) }
  end

  private

  def rewrite(raw_model, column, type, encrypted_only: false)
    raw_model.where.not(column => nil).find_each do |row|
      value = row[column]
      already_encrypted = decrypts?(type, value)
      next if encrypted_only ? !already_encrypted : already_encrypted

      row.update_column(column, yield(type, value))
    end
  end

  def decrypts?(type, value)
    type.deserialize(value)
    true
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end
end
