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

  # Raised only from #admit; HomeWorkspaceProtectedError is a lifecycle guard and
  # deliberately not a subclass (#689). Rescue this where every admission outcome
  # is handled the same way; rescue the subclasses where they branch.
  AdmissionError = Class.new(StandardError)

  # Non-disclosing by contract: an outsider must not learn which lifecycle state blocked them.
  # See /docs/developer/architecture (Key Concepts).
  NotAdmittableError = Class.new(AdmissionError)
  # Typed so callers never match the humanized validation string (locale edits break it).
  AlreadyMember = Class.new(AdmissionError)
  AtCapacity = Class.new(AdmissionError)

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

  # Virtual, never persisted: backs the operator-create form's target-owner
  # email (Workspace.create_for_owner_email). A real attribute, not a
  # controller-local variable, so a format failure attaches to THIS field
  # instead of :base and UI::FormBuilder's error_for can wire it up.
  attr_accessor :owner_email

  # _commit, not after_create: enqueuing into Solid Queue's SQLite under the primary write lock is a lock-ordering hazard.
  after_create_commit :notify_workspace_created, if: -> { created_by.present? }

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true
  validates :max_members, numericality: { greater_than: 0 }
  validate :personal_workspaces_are_invite_only
  validate :join_policy_must_be_permitted_by_instance
  # allow_nil, not allow_blank: every OTHER Workspace creation path never
  # touches owner_email (stays nil) and must stay unaffected by this rule;
  # create_for_owner_email coerces its input to a String (a missing key
  # becomes ""), so the operator path never takes the exemption.
  validates :owner_email, format: { with: User::EMAIL_FORMAT }, allow_nil: true

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
    ms.detect { |m| m.owner? && m.kept? }&.user
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

  # The operator-create verb: an existing user owns the workspace outright;
  # an unknown email makes the operator the interim owner and gets an
  # Owner-role invitation. The invitation is issued AFTER create_owned's
  # transaction commits because bulk_invite! enqueues mail, and enqueuing
  # inside the primary write transaction is the hazard the
  # after_create_commit note above describes. A failed invitation leaves a
  # workspace the operator owns and can invite from by hand. See
  # /docs/developer/operations (The operator becomes the owner).
  def self.create_for_owner_email(attrs, operator:)
    # Coerced to a String first: a missing key would otherwise arrive as nil,
    # pass the format validation's allow_nil, and — because bulk_invite!
    # skips a blank instead of raising — hand the workspace to the operator
    # with no invitation and no error.
    attrs = attrs.to_h.symbolize_keys
    attrs[:owner_email] = attrs[:owner_email].to_s.strip
    owner = User.find_by(email_address: attrs[:owner_email])
    workspace = create_owned(attrs, owner: owner || operator)
    if workspace.persisted? && owner.nil?
      Invitation.bulk_invite!(
        workspace: workspace, emails: [ attrs[:owner_email] ],
        role: Role.system_default!("owner"), invited_by: operator
      )
    end
    workspace
  end

  private

  # A workspace's own audit rows belong to it. Without this, Trackable falls
  # through to Current.workspace — nil at signup, so the workspace.created row
  # was written unreachable by any feed; and the PREVIOUS workspace when a
  # signed-in user created a second one from inside the first, so the row
  # landed in the wrong tenant's feed (#1084). Every other Trackable includer
  # that owns a workspace already answers this for itself.
  def activity_workspace
    self
  end

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
