# Shared broadcast pattern — models include this and override broadcast_target
# to specify what stream to broadcast to. Override self.broadcast_events to
# customize which lifecycle events trigger broadcasts (default: create + update).
module Broadcastable
  extend ActiveSupport::Concern

  included do
    after_commit :broadcast_changes, on: broadcast_events
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
