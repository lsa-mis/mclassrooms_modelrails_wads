# One password sign-in attempt: every failure carries the same error and costs one hash.
# See /docs/developer/security (Password sign-in).
class PasswordSignIn
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email_address, :string
  attribute :password, :string

  def user
    return @user if defined?(@user)

    @user = authenticated_user
    errors.add(:base, :failure, message: I18n.t("sessions.create.failure")) if @user.nil?
    @user
  end

  private

  def authenticated_user
    return if password.blank?

    candidate = User.find_by(email_address: email_address)
    matched = candidate&.has_password? ? candidate.authenticate(password) : hash_for_timing
    return candidate if matched && !candidate.locked?

    candidate.register_failed_login! if candidate && !candidate.locked?
    nil
  end

  # A miss pays the hash a hit pays, as Rails' authenticate_by does; otherwise timing names real accounts.
  def hash_for_timing
    User.new(password: password)
    false
  end
end
