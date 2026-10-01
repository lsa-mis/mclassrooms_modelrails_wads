class ActivityLog < ApplicationRecord
  # Which records a ledger query names: a person or workspace (no project domain in this
  # fork). People match through User::Search; filtering is ActivityLog.matching_any's job.
  class Search
    # Bounds the two SQL branches; names carry their own cap.
    RESULT_LIMIT = 50

    attr_reader :query, :users, :workspaces, :projects

    def self.resolve(query, reach:)
      needle = query.to_s.strip.downcase.presence
      return new(query: nil) unless needle

      people = User::Search.resolve(needle)
      new(query: needle, names_skipped: people.names_skipped?,
          users: people.users,
          workspaces: matching_workspaces(needle, reach))
    end

    # A query is text, never a pattern: "ac_e" matches "Ac_e" and not "Acme"
    # (#454, the same ruling the members page's search rests on). `ESCAPE` is
    # not optional — `sanitize_sql_like` backslash-escapes the wildcards, and
    # without the clause SQLite reads that backslash as a literal character.
    ESCAPED_LIKE = "ESCAPE '\\'".freeze

    # PUBLIC, and a relation rather than an array: the ledger's workspace picker
    # needs the same match with its own limit and a count, and the LIKE/ESCAPE
    # doctrine above must have exactly one home. Workspace names are plaintext
    # (unlike user names), so this is ordinary SQL.
    def self.workspaces_matching(needle, reach:)
      reach.where("LOWER(workspaces.name) LIKE :name #{ESCAPED_LIKE} OR workspaces.slug = :slug",
                  name: "%#{Workspace.sanitize_sql_like(needle.to_s.strip.downcase)}%",
                  slug: needle.to_s.strip.downcase)
    end

    def self.matching_workspaces(needle, reach)
      workspaces_matching(needle, reach: reach).limit(RESULT_LIMIT).to_a
    end
    private_class_method :matching_workspaces

    def initialize(query:, users: [], workspaces: [], projects: [], names_skipped: false)
      @query, @users, @workspaces, @projects, @names_skipped =
        query, users, workspaces, projects, names_skipped
    end

    def blank? = query.nil?
    def matched? = users.any? || workspaces.any? || projects.any?
    def names_skipped? = @names_skipped
  end
end
