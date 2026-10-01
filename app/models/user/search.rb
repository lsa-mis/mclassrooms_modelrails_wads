class User < ApplicationRecord
  # The one home for matching a person: email equals in SQL (deterministic), names
  # decrypt and match in Ruby. See /docs/developer/security (Personal Data at Rest).
  class Search
    # ~24 ms of decrypt CPU at 0.012 ms a row; above it, exact-email lookup only.
    NAME_SEARCH_LIMIT = 2_000
    # A one-letter query must not build an OR list of the whole instance.
    RESULT_LIMIT = 50

    attr_reader :query, :users

    # `scope` is the searcher's reach, so narrowing reach narrows the search.
    def self.resolve(query, scope: User.all)
      needle = query.to_s.strip.downcase.presence
      return new(query: nil) unless needle

      skipped = scope.count > NAME_SEARCH_LIMIT
      new(query: needle, names_skipped: skipped, users: matching(needle, scope, skipped))
    end

    def self.matching(needle, scope, skipped)
      found = Array(scope.find_by(email_address: needle))
      return found if skipped

      scope.select(:id, :first_name, :last_name).find_each do |user|
        break if found.size >= RESULT_LIMIT

        found << user if user.id != found.first&.id && matches_name?(user, needle)
      end
      found
    end
    private_class_method :matching

    def self.matches_name?(user, needle)
      [ user.full_name, user.first_name, user.last_name ]
        .any? { |value| value.to_s.downcase.include?(needle) }
    end
    private_class_method :matches_name?

    def initialize(query:, users: [], names_skipped: false)
      @query, @users, @names_skipped = query, users, names_skipped
    end

    def blank? = query.nil?
    def ids = users.map(&:id)
    def names_skipped? = @names_skipped
    # The scan hit the cap; a caller showing results must say so.
    def capped? = users.size >= RESULT_LIMIT
  end
end
