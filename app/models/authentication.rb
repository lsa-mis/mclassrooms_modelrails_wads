class Authentication < ApplicationRecord
  belongs_to :user

  enum :provider, { email: "email", google: "google", github: "github" }

  include Broadcastable

  def self.broadcast_events
    [ :create, :update, :destroy ]
  end

  def self.display_name_for(provider_string)
    I18n.t("authentication.providers.#{provider_string}",
           default: provider_string.to_s.titleize)
  end

  def display_provider
    self.class.display_name_for(provider)
  end

  validates :provider, presence: true
  validates :uid, presence: true
  validates :provider, uniqueness: { scope: :user_id }
  validates :uid, uniqueness: { scope: :provider }
  validates :avatar_url, format: { with: /\Ahttps:\/\/\S+\z/i }, allow_blank: true

  TOKEN_LIFETIME = 24.hours

  # Stateless, signed email-verification token (Rails generates_token_for).
  # Nothing is stored: the token carries the record id and a payload, and
  # find_by_token_for re-derives it. Embedding verified_at makes the link
  # single-use — once the auth is verified the payload changes, so any
  # previously-issued link stops validating. Expiry is enforced by the token
  # itself (no verification_sent_at bookkeeping, no collision retries).
  generates_token_for :email_verification, expires_in: TOKEN_LIFETIME do
    verified_at
  end

  scope :verified, -> { where.not(verified_at: nil) }
  scope :pending,  -> { where(verified_at: nil) }
  scope :oauth,    -> { where.not(provider: "email") }

  def verified?
    verified_at.present?
  end

  # An auth is pending until it's verified. Every unverified auth is created
  # with a verification email on its way (token minted on demand), so
  # "not verified" is exactly "awaiting verification".
  def pending?
    verified_at.nil?
  end

  # True iff (a) this auth is verified AND (b) it's the only verified auth for the user.
  # Used by the destroy guard to prevent removing the user's last verified sign-in method.
  def only_verified_remaining?
    verified? && user.authentications.verified.count <= 1
  end

  def verify!
    update!(verified_at: Time.current)
  end

  def claim_pending_invitation!(user)
    return if pending_invitation_token.blank?

    ApplicationRecord.transaction do
      Invitation.consume!(token: pending_invitation_token, user: user, expected_email: user.email_address)
      update!(pending_invitation_token: nil)
    end
  rescue Invitation::EmailMismatch
    # Wrong-address claim: the transaction rolled back (token still set), so
    # clear the parked token here — it can never be claimed by this user — and
    # re-raise so the caller can tell the user why they weren't added.
    update!(pending_invitation_token: nil)
    raise
  end

  # Reshape 2b: claim a workspace join-link token parked at signup time.
  # Stale link conditions (revoked, policy reverted, instance no longer
  # permits :open_link, workspace suspended) are treated as silent no-ops —
  # clear the token and continue, so email verification isn't blocked by a
  # workspace whose join policy changed mid-flight. A visitor who was never
  # a member must not learn the workspace is locked. Capacity/already-member
  # errors propagate up so the caller can surface them.
  def claim_pending_join_link!(user)
    return if pending_join_link_token.blank?

    link = WorkspaceJoinLink.active.find_by(token: pending_join_link_token)

    if link.nil? || !link.workspace.open_join? || link.workspace.suspended?
      update!(pending_join_link_token: nil)
      return
    end

    # The token is a one-shot claim: verify never retries, so once we attempt
    # admission the token is spent regardless of outcome. Clearing it lives in
    # `ensure` (not bundled in admit's transaction) so a terminal failure like
    # capacity rolls back the membership but does NOT resurrect the token.
    begin
      link.workspace.admit(user, role: link.workspace.default_self_join_role)
    ensure
      update!(pending_join_link_token: nil)
    end
  end

  private

  def broadcast_target
    [ user, :authentications ]
  end
end
