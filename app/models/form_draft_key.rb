# Derives the per-user client-side draft-encryption key (delivered via meta
# tag, imported by the form-draft Stimulus controller) and its public scope
# digest used to namespace localStorage entries. Key derivation goes through
# Rails.application.key_generator so it participates in secret rotation;
# rotating secret_key_base intentionally invalidates outstanding drafts.
class FormDraftKey
  SCOPE_LABEL = "form-draft-scope"

  def self.for(user)
    Rails.application.key_generator.generate_key("form-draft:#{user.id}", 32)
  end

  def self.scope_for(user)
    OpenSSL::HMAC.hexdigest("SHA256", self.for(user), SCOPE_LABEL).first(8)
  end
end
