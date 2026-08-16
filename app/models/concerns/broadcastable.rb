# Shared broadcast pattern — override broadcast_target (stream) and
# self.broadcast_events (default: create + update). Three separate callbacks so
# the `if:` predicates read broadcast_events lazily — an override registered
# after `include Broadcastable` still takes effect.
module Broadcastable
  extend ActiveSupport::Concern

  included do
    # Lambda form (not symbol form) is deliberate: ActiveSupport dedupes three
    # `after_*_commit :broadcast_changes` registrations into one because they
    # normalize to the same callback key. Each lambda is a unique object, so
    # all three callbacks register independently.
    after_create_commit  -> { broadcast_changes }, if: -> { self.class.broadcast_events.include?(:create) }
    after_update_commit  -> { broadcast_changes }, if: -> { self.class.broadcast_events.include?(:update) }
    after_destroy_commit -> { broadcast_changes }, if: -> { self.class.broadcast_events.include?(:destroy) }
  end

  class_methods do
    def broadcast_events
      [ :create, :update ]
    end
  end

  private

  def broadcast_target
    self
  end

  def broadcast_changes
    broadcast_refresh_to broadcast_target
  rescue StandardError => e
    # Intentionally broad: broadcast failures must NEVER break model saves.
    # The broadcast adapter (Solid Cable, Redis, etc.) can raise a wide range
    # of exceptions depending on the backing store. Logging at error level
    # ensures visibility while keeping the model save path reliable.
    Rails.logger.error("Broadcast failed for #{self.class.name}##{id}: #{e.class}: #{e.message}")
  end
end
