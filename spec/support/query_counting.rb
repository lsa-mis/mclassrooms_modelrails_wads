# frozen_string_literal: true

# Counts real (non-cached, non-schema) SQL statements touching the given table
# during the block. For N+1 regression specs where the contract is "exactly one
# query for the whole candidate set" — the SQL-level sibling of the mock-based
# `.once` precedent in spec/lib/notification_broadcaster_spec.rb.
module QueryCounting
  def count_queries_touching(table, &block)
    count_statements_touching(table, ->(_sql) { true }, &block)
  end

  # Reads only: a loop that legitimately writes per record would drown the signal (#1048).
  def count_selects_touching(table, &block)
    count_statements_touching(table, ->(sql) { sql.lstrip.match?(/\ASELECT\b/i) }, &block)
  end

  private

  def count_statements_touching(table, predicate)
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      sql = payload[:sql].to_s
      next unless sql.include?(table.to_s)

      count += 1 if predicate.call(sql)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end
end

RSpec.configure do |config|
  config.include QueryCounting
end
