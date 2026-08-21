# frozen_string_literal: true

# Counts real (non-cached, non-schema) SQL statements touching the given table
# during the block. For N+1 regression specs where the contract is "exactly one
# query for the whole candidate set" — the SQL-level sibling of the mock-based
# `.once` precedent in spec/lib/notification_broadcaster_spec.rb.
module QueryCounting
  def count_queries_touching(table)
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]
      count += 1 if payload[:sql].to_s.include?(table.to_s)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end
end

RSpec.configure do |config|
  config.include QueryCounting
end
