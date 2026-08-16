class Workspace < ApplicationRecord
  include Discardable
  include Archivable
  include Suspendable
  include Trackable
  include Broadcastable
  include Sluggable

  # Raised when an owner tries to archive/delete a home workspace (personal or
  # the :shared instance workspace). Defense in depth behind WorkspacePolicy —
  # covers console/direct-call paths the policy never sees.
  HomeWorkspaceProtectedError = Class.new(StandardError)

  # Raised by #admit when a workspace won't accept new members (archived,
  # suspended, or deleted). Distinct from Suspendable::SuspendedError so its
  # rescue can map to GENERIC, non-disclosing copy — an outsider following a
  # join link/invitation must not learn which lifecycle state blocked them.
  NotAdmittableError = Class.new(StandardError)
  # Typed outcomes of #admit — callers rescue these instead of matching the
  # humanized validation string (which breaks on any locale edit). Sibling of
  # the passkeys typed-error hierarchy.
  AlreadyMember = Class.new(StandardError)
  AtCapacity = Class.new(StandardError)

  has_one_attached :logo
  has_one_attached :logo_original
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :roles, dependent: :destroy
  has_many :invitations, as: :invitable, dependent: :destroy

  enum :plan, { free: "free", pro: "pro", enterprise: "enterprise" }

  # Per-workspace join policy. Composes with the instance-level
  # SignupPolicy.permits_strategy? allowlist. See app/docs/developer/presets.md
  # and docs/reshape-2-per-workspace-join-policy-spec.md.
  enum :join_policy, { invite: "invite", open_link: "open_link" }, default: "invite"

  has_many :join_links, class_name: "WorkspaceJoinLink", dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :logo,
    content_type: IMAGE_CONTENT_TYPES,
    size: { less_than: 5.megabytes }
  validates :logo_original,
    content_type: IMAGE_CONTENT_TYPES,
    size: { less_than: 10.megabytes }
  validates :slug, presence: true, uniqueness: true
  validates :max_members, numericality: { greater_than: 0 }
  validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true
  validates :logo_source, inclusion: { in: %w[upload initials] }
  validate :personal_workspaces_are_invite_only
  validate :join_policy_must_be_permitted_by_instance

  def self.broadcast_events
    [ :update ]
  end

  # Lifecycle status with explicit precedence — the single authoritative
  # answer to "what state is this record in". Display goes through
  # LifecycleHelper#lifecycle_status_label, never status.to_s.
  # NB: Time === ActiveSupport::TimeWithZone is true (ActiveSupport
  # special-cases case-equality) — don't "fix" the Time patterns.
  def status
    case [ discarded_at, suspended_at, archived_at ]
    in [ Time, * ]     then :discarded
    in [ _, Time, * ]  then :suspended
    in [ _, _, Time ]  then :archived
    else                    :active
    end
  end

  # A "home" workspace is the user's personal workspace or, under the :shared
  # posture, the instance's single shared workspace. Home workspaces are
  # exempt from owner archive/delete (there's nowhere for the user to land).
  # Compared by slug — never a query or AR identity — so it stays correct
  # regardless of the workspace's own lifecycle state (see design finding #5).
  def home?
    personal? || (TenancyConfig.shared? && slug == TenancyConfig.shared_workspace_slug)
  end

  # A workspace accepts NEW members (via join link, invitation, or signup
  # claim) only while active. Existing-member management is separate — see
  # Membership#reactivate!. Derived from `status` (not a hand-rolled
  # conjunction) so a future lifecycle state fails CLOSED here automatically
  # instead of silently admitting — the exact bug class this guard exists for.
  def admittable?
    status == :active
  end

  # Guarded lifecycle mutators. `transaction do` opens BEGIN IMMEDIATE on the
  # SQLite adapter, making lock!-then-guard atomic check-then-act; `next` (not
  # `return`) exits early by committing rather than rolling back.
  # See /docs/developer/architecture (Concurrency).
  def archive!
    transaction do
      lock!
      next if archived?
      raise HomeWorkspaceProtectedError if home?
      raise Suspendable::SuspendedError if suspended?
      super
    end
  end

  def unarchive!
    transaction do
      lock!
      next unless archived?
      raise Suspendable::SuspendedError if suspended?
      super
    end
  end

  def discard!
    transaction do
      lock!
      next if discarded?
      raise HomeWorkspaceProtectedError if home?
      raise Suspendable::SuspendedError if suspended?
      super
    end
  end

  def to_param
    slug
  end

  def initials
    name.split.map(&:first).take(2).join.upcase
  end

  def owner
    # Uses detect (not joins + find_by) so it works from preloaded
    # memberships without firing a per-row query in list views.
    memberships.detect { |m| m.role.slug == "owner" }&.user
  end

  # All Users holding an owner-role kept membership. Two-path on purpose:
  # loaded `memberships` filter in-memory (hot path — the Leave button calls
  # `.owners.size` per render); unloaded issues a fresh query so notifier
  # recipient resolution never reads a stale roster.
  # See /docs/developer/architecture (Owner Lookup).
  def owners
    relation = memberships.loaded? ? memberships : memberships.kept.includes(:role, :user)
    relation
      .reject(&:discarded?)
      .select { |m| m.role.slug == "owner" }
      .map(&:user)
      .compact
  end

  def available_logo_sources
    %w[upload initials]
  end

  def identity
    WorkspaceIdentity.new(self)
  end

  def effective_roles
    Role.where(workspace_id: [ nil, id ])
  end

  # True iff this workspace exposes a shareable join link AND personal
  # workspaces are excluded (hard guard) AND the instance allowlist permits
  # :open_link. Composes the three layers so callers don't have to.
  def open_join?
    open_link? && !personal? && SignupPolicy.permits_strategy?(:open_link)
  end

  # Whether an active open-link join can be admitted right now: the join policy
  # is open AND the workspace is in an admittable state (not archived/suspended/
  # deleted). The single home for the "open_join? && admittable?" rule the join
  # claim/resolution sites share. (SignupPolicy's gate deliberately checks only
  # open_join? — admittable? is re-checked here at claim time.)
  def accepting_open_joins?
    open_join? && admittable?
  end

  # Role granted to users self-joining via an open-link. Pinned to the
  # lowest-privilege system role for safety (Reshape 1 reasoning); per-link
  # or per-workspace role customization is deferred until requested.
  def default_self_join_role
    Role.find_by!(slug: "member", workspace_id: nil)
  end

  # Single membership-grant entry point. Both the Invitation flow and the
  # open-link self-join flow (Reshape 2) call this — keeping the lock,
  # capacity check, discarded-reactivation, and :shared-posture role
  # reconciliation in one place. Wrapped in a transaction so direct callers
  # are safe; nested calls join the surrounding transaction.
  # granted_by: audit provenance only (G) — the inviter, when an invitation
  # acceptance is what created the membership. Never affects admission logic.
  def admit(user, role:, granted_by: nil)
    transaction do
      lock!
      raise NotAdmittableError unless admittable?
      existing = memberships.find_by(user: user)
      if existing&.discarded?
        existing.undiscard!
      elsif existing && !existing.discarded?
        if TenancyConfig.shared?
          # Under :shared, the User#onboard_workspace callback pre-creates a
          # placeholder Member membership. Reconcile: adopt the new role
          # rather than treating it as duplicate-accept. Solo-default
          # (:personal) semantics are preserved exactly.
          existing.update!(role: role) unless existing.role_id == role.id
        else
          raise AlreadyMember
        end
      else
        raise AtCapacity if memberships.kept.count >= max_members
        memberships.create!(user: user, role: role, granted_by: granted_by)
      end
    end
  end

  private

  def personal_workspaces_are_invite_only
    return unless personal? && !invite?
    errors.add(:join_policy, :personal_must_be_invite)
  end

  def join_policy_must_be_permitted_by_instance
    return if SignupPolicy.permits_strategy?(join_policy)
    errors.add(:join_policy, :not_permitted_by_instance)
  end
end
