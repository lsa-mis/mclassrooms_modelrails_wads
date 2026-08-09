# frozen_string_literal: true

# Deletes sessions past their idle or absolute timeout. Housekeeping only —
# expiry is already enforced at read time in Authenticatable#find_session_by_cookie
# (expired rows resolve to nil, fail-closed), so a delayed sweep never opens a
# security window; it just keeps the table from accumulating dead rows.
#
# Batched delete_all: SQLite serializes write transactions, so a large one-shot
# delete could block sign-ins; per-batch transactions release the writer lock
# between rounds. No destroy callbacks or dependent cascades on Session (the only
# FK is Session -> users), so delete_all is correct and instantiates nothing.
class ExpiredSessionsSweepJob < ApplicationJob
  queue_as :default

  def perform
    Session.expired.in_batches(of: 100, &:delete_all)
  end
end
