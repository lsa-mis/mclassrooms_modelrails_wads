class Workspace < ApplicationRecord
  include Discardable
  include Archivable
  include Suspendable
  include Trackable
  include Broadcastable
  # `name` stays plaintext while other personal data is encrypted (#902,
  # ruling R3): the slug is the name parameterized, and sits in every URL.
  include Sluggable
  include Branding
  include Admission

  # Defense in depth behind WorkspacePolicy — covers console/direct-call paths the policy never sees.
  HomeWorkspaceProtectedError = Class.new(StandardError)

  # Non-disclosing by contract: an outsider must not learn which lifecycle state blocked them.
  # See /docs/developer/architecture (Key Concepts).
  NotAdmittableError = Class.new(StandardError)
  # Typed so callers never match the humanized validation string (locale edits break it).
  AlreadyMember = Class.new(StandardError)
  AtCapacity = Class.new(StandardError)

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :roles, dependent: :destroy
  has_many :invitations, as: :invitable, dependent: :destroy

  # :delete_all because ActivityLog#readonly? refuses instance destroy — a reviewed bypass (#921).
  # See /docs/developer/architecture (Activity Tracking).
  has_many :activity_logs, dependent: :delete_all

  enum :plan, { free: "free", pro: "pro", enterprise: "enterprise" }

  # Composes with the instance-level SignupPolicy.permits_strategy? allowlist. See /docs/developer/presets.
  enum :join_policy, { invite: "invite", open_link: "open_link" }, default: "invite"

  has_many :join_links, class_name: "WorkspaceJoinLink", dependent: :destroy

  # Gate for the created notification: .create_owned sets it; seeds, fixtures and signup-time creation stay silent.
  # See /docs/developer/notifications (The actor rule).
  attr_accessor :created_by

  # _commit, not after_create: enqueuing into Solid Queue's SQLite under the primary write lock is a lock-ordering hazard.
  after_create_commit :notify_workspace_created, if: -> { created_by.present? }

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true
  validates :max_members, numericality: { greater_than: 0 }
  validate :personal_workspaces_are_invite_only
  validate :join_policy_must_be_permitted_by_instance

  def self.broadcast_events
    [ :update ]
  end

  # Time === ActiveSupport::TimeWithZone is true (case-equality is special-cased) — don't "fix" the Time patterns.
  # Display goes through LifecycleHelper#lifecycle_status_label, never status.to_s.
  def status
    case [ discarded_at, suspended_at, archived_at ]
    in [ Time, * ]     then :discarded
    in [ _, Time, * ]  then :suspended
    in [ _, _, Time ]  then :archived
    else                    :active
    end
  end

  # Compared by slug, never a query, so it stays correct whatever the workspace's own lifecycle state.
  def home?
    personal? || (TenancyConfig.shared? && slug == TenancyConfig.shared_workspace_slug)
  end

  # `next`, not `return`: an early exit commits nothing. See /docs/developer/architecture (Concurrency).
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

  def owner
    # detect over preloaded memberships, no per-row query in lists. See /docs/developer/architecture (Owner Lookup).
    ms = memberships.loaded? ? memberships : memberships.includes(:role, :user)
    ms.detect(&:owner?)&.user
  end

  # Always a fresh query, even when memberships is loaded. See /docs/developer/architecture (Owner Lookup).
  def owners
    memberships.kept
      .joins(:role)
      .merge(Role.owner)
      .includes(:user)
      .map(&:user)
      .compact
  end

  def identity
    WorkspaceIdentity.new(self)
  end

  def effective_roles
    Role.where(workspace_id: [ nil, id ])
  end

  # Atomic workspace + owner-membership creation (#676): the workspace INSERT
  # and the owner membership commit or roll back together.
  # See /docs/developer/architecture (Concurrency).
  def self.create_owned(attrs, owner:)
    workspace = new(attrs)
    workspace.created_by = owner
    transaction do
      if workspace.save
        workspace.memberships.create!(user: owner, role: Role.system_default!("owner"))
      end
    end
    workspace
  end

  private

  def notify_workspace_created
    WorkspaceCreatedNotifier.with(record: self, creator: created_by).deliver(nil)
  end

  def personal_workspaces_are_invite_only
    return unless personal? && !invite?
    errors.add(:join_policy, :personal_must_be_invite)
  end

  def join_policy_must_be_permitted_by_instance
    return if SignupPolicy.permits_strategy?(join_policy)
    errors.add(:join_policy, :not_permitted_by_instance)
  end
end
