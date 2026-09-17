module Suspendable
  extend ActiveSupport::Concern

  # Raised by guarded lifecycle mutators when an owner attempts a transition
  # on a suspended (user-facing: "locked") record. Concern-level home so
  # Workspace and Project share one class (Project raises it via its
  # workspace's state).
  SuspendedError = Class.new(StandardError)

  included do
    scope :not_suspended, -> { where(suspended_at: nil) }
    scope :suspended,     -> { where.not(suspended_at: nil) }
  end

  # Guarded like Workspace#archive!/#discard!: lock-then-check inside the
  # transaction so a double submit or two operators can't bump suspended_at
  # twice or write two "locked" activity rows. `next` on the no-op saves
  # nothing, so Broadcastable's refresh doesn't fire. Returns the outcome so
  # callers can report it. See /docs/developer/architecture (Concurrency).
  def suspend!
    transaction do
      lock!
      next :already_suspended if suspended?
      update!(suspended_at: Time.current)
      :suspended
    end
  end

  def unsuspend!
    transaction do
      lock!
      next :not_suspended unless suspended?
      update!(suspended_at: nil)
      :unsuspended
    end
  end

  def suspended?
    suspended_at.present?
  end
end
