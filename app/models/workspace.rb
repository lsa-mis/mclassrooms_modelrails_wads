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

  has_one_attached :logo
  has_one_attached :logo_original
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :roles, dependent: :destroy
  has_many :invitations, as: :invitable, dependent: :destroy
  has_many :projects, dependent: :destroy

  enum :plan, { free: "free", pro: "pro", enterprise: "enterprise" }

  # Per-workspace join policy. Composes with the instance-level
  # SignupPolicy.permits_strategy? allowlist. See app/docs/developer/presets.md
  # and docs/reshape-2-per-workspace-join-policy-spec.md.
  enum :join_policy, { invite: "invite", open_link: "open_link" }, default: "invite"

  has_many :join_links, class_name: "WorkspaceJoinLink", dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :logo,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 5.megabytes }
  validates :logo_original,
    content_type: %w[image/png image/jpeg image/gif image/webp],
    size: { less_than: 10.megabytes }
  validates :slug, presence: true, uniqueness: true
  validates :max_members, numericality: { greater_than: 0 }
  validates :max_projects, numericality: { greater_than: 0 }
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

  # Guarded lifecycle mutators. Plain `transaction do` opens BEGIN IMMEDIATE
  # on Rails 8.1's SQLite adapter (write lock taken before the first read),
  # so lock!-then-guard is atomic check-then-act. lock! raises on records
  # with unsaved changes — these mutators require clean records.
  # `next` (not `return`) exits early: it commits the empty transaction;
  # `return` would roll back.
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
      projects.kept.find_each(&:discard!)
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

  # Returns all User records currently holding an owner-role kept membership
  # in this workspace. Used by the capacity-approaching sweep to broadcast a
  # billing alert to every owner, and exposed for future ownership-management
  # UIs that need the full owner roster (vs. `#owner`, which returns just one).
  #
  # Two-path implementation to avoid an N+1 on `workspaces#index` without
  # introducing staleness on mutating call sites:
  #
  # * When `memberships` is already loaded (controller preloads
  #   `memberships: [:role, { user: ... }]` for the index page), filter the
  #   in-memory Array — zero extra queries per row. This is the hot path:
  #   `MembershipPolicy#destroy?` calls `.owners.size` on every Leave-button
  #   render.
  # * When `memberships` is NOT loaded (notifier recipient resolution after
  #   a membership mutation), issue a fresh narrow query so we see the
  #   latest committed state. The notifiers run after mutations that change
  #   the owner roster; we cannot reuse a cached Array there without risk
  #   of stale reads.
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

  def effective_roles
    Role.where(workspace_id: [ nil, id ])
  end

  # True iff this workspace exposes a shareable join link AND personal
  # workspaces are excluded (hard guard) AND the instance allowlist permits
  # :open_link. Composes the three layers so callers don't have to.
  def open_join?
    open_link? && !personal? && SignupPolicy.permits_strategy?(:open_link)
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
  def admit(user, role:)
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
          raise ActiveRecord::RecordInvalid.new(self), "User is already a member"
        end
      else
        raise ActiveRecord::RecordInvalid.new(self), "Workspace is at capacity" if memberships.kept.count >= max_members
        memberships.create!(user: user, role: role)
      end
    end
  end

  private

  def personal_workspaces_are_invite_only
    return unless personal? && !invite?
    errors.add(:join_policy, :personal_must_be_invite, message: I18n.t("errors.messages.personal_must_be_invite", default: "must be 'invite' for personal workspaces"))
  end

  def join_policy_must_be_permitted_by_instance
    return if SignupPolicy.permits_strategy?(join_policy)
    errors.add(:join_policy, :not_permitted_by_instance, message: I18n.t("errors.messages.not_permitted_by_instance", default: "is not permitted by this instance"))
  end
end
