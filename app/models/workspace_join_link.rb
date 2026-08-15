class WorkspaceJoinLink < ApplicationRecord
  # Bearer token stored only as a SHA256 digest (mirrors MagicLinkToken). The
  # plaintext lives in the shared URL and is surfaced once, on create/rotate,
  # via #plaintext_token — never re-read from the database. Revocability is why
  # this is a stored record (vs. a signed-stateless token): `revoked_at` makes
  # individual links killable and the partial unique index keeps one active per
  # workspace. Rotation is revoke-then-create in JoinLinksController.
  attr_reader :plaintext_token

  validates :token_digest, presence: true, uniqueness: true

  belongs_to :workspace
  belongs_to :created_by, class_name: "User"

  scope :active, -> { where(revoked_at: nil) }

  before_validation :generate_token, on: :create

  # One formula, so lookup and insert can never disagree (see MagicLinkToken).
  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_active(token)
    find_active_by_digest(digest(token))
  end

  # For the deferred-OAuth claim, where the digest is parked directly on the
  # Authentication (no plaintext to re-digest).
  def self.find_active_by_digest(token_digest)
    active.find_by(token_digest: token_digest)
  end

  # Admit `user` through this link, at the pinned self-join role — but only if
  # the workspace still accepts open-link joins (its policy may have reverted or
  # it may have gone non-admittable since the token was parked). A no-op for a
  # stale link. The single home for "join through this link"; both the signup
  # (session-token) and deferred-OAuth (parked-digest) claim paths call it, so
  # the accepting-state guard and self-join role can't diverge between them.
  # Raises Workspace::AlreadyMember / Workspace::AtCapacity from Workspace#admit;
  # callers decide how to treat those.
  def admit(user)
    return unless workspace.accepting_open_joins?

    workspace.admit(user, role: workspace.default_self_join_role)
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  # Non-secret display stub for settings once the plaintext is gone. Uses the
  # digest tail (public) so admins can tell one link from another; never the
  # plaintext, which no longer exists at rest.
  def masked_token
    "…#{token_digest.to_s.last(6)}"
  end

  private

  def generate_token
    return if token_digest.present?

    @plaintext_token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(@plaintext_token)
  end
end
