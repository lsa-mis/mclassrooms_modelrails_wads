class User < ApplicationRecord
  # How a query names a PERSON, and the only home for that rule.
  #
  # Two branches, because the two columns are encrypted differently (#902):
  # `email_address` is deterministic, so SQL can equal it but never match
  # inside it; `first_name`/`last_name` are not, so a name is matched the one
  # way this app sanctions — load, decrypt, plain case-insensitive substring in
  # Ruby. `WorkspaceRoster`'s technique at instance scale, which is why the two
  # caps exist. See /docs/developer/security (Personal Data at Rest).
  #
  # It lives here rather than on `ActivityLog::Search` because it is a fact
  # about User's encryption, and because two callers now need it: the ledger's
  # search box and the operations users index. Same reason
  # `ActivityLog::Search.workspaces_matching` is public — the doctrine, and the
  # CPU budget that goes with it, gets exactly one home.
  class Search
    # The decrypt pass measured 0.012 ms a row, so the cap is about 24 ms of
    # CPU per search — a request's worth, not a page's. Above it names are not
    # searched at all and the query falls back to the exact-email lookup, which
    # is SQL.
    NAME_SEARCH_LIMIT = 2_000
    # A one-letter query must not build an OR list of the whole instance.
    RESULT_LIMIT = 50

    attr_reader :query, :users

    # `scope` is the reach to search within — `User.all` for the ledger, an
    # operator's `operated_users` for the operations index, so narrowing reach
    # later narrows the search with it.
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
    # The scan stopped at the cap, so there may be matches nobody has seen.
    # A caller that shows results must say so rather than cap silently.
    def capped? = users.size >= RESULT_LIMIT
  end
end
