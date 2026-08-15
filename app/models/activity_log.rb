class ActivityLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :trackable, polymorphic: true
  belongs_to :workspace, optional: true

  # The audit trail is best-effort to write (Trackable rescues rather than
  # failing the business operation — CLAUDE.md deviation #4) and immutable
  # after: persisted rows refuse instance-level update/destroy. Relation-level
  # bypasses (update_all/delete_all) are fenced by
  # spec/code_smells/activity_log_immutability_spec.rb, where a future
  # retention job (#438) gets its explicit carve-out.
  def readonly? = persisted?

  enum :visibility, { workspace: "workspace", admin: "admin" }, default: "workspace"

  validates :action, presence: true

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }
  scope :visible, -> { where(visibility: "workspace") }
  scope :recent, -> { order(created_at: :desc).limit(20) }
end
