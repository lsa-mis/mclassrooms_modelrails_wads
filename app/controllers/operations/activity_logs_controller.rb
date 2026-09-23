module Operations
  class ActivityLogsController < BaseController
    ROWS         = %w[25 50 100 all].freeze
    # The two columns the ledger can order in SQL. Who is not among them: actor
    # names are encrypted (operations.md, "What it deliberately does not do").
    SORTS = %w[created_at workspace].freeze
    DEFAULT_SORT = "created_at"
    DEFAULT_ROWS = "50"
    # "All" is all of the current filter and window, up to this many rows.
    # The cost is the page, not the decrypt (0.012 ms a row, ActivityLog::Search):
    # 500 rows of <details> is already a long document, and an uncapped All on
    # "All time" is one that never finishes rendering.
    ALL_ROWS = 500
    # The workspace filter's reach is `Workspace.kept` — EVERY tenant on the
    # instance — so an option list here grows with the business. Past this many
    # the control stops being a list and becomes a search, and the list is not
    # built at all. That, not a cap, is the fix: a workspace missing from a
    # capped list is unselectable with nothing to say so.
    #
    # The threshold exists because this is a fork template. Nobody is watching a
    # given fork's instance to notice the day it crosses the line, so the page
    # has to cross it by itself. 100 options is roughly 6 KB of markup, re-sent
    # on every full-page navigation — sorting and paging both are.
    WORKSPACE_PICKER_LIMIT = 100
    # How many candidates a search offers before it says there are more. Honest
    # truncation: the page states the count it did not show.
    WORKSPACE_CANDIDATE_LIMIT = 20
    # How many people the "most active" strip names. Few enough to read at a
    # glance — it answers "who has been busiest here", not "here is a breakdown".
    TOP_ACTORS = 5

    def index
      authorize [ :operations, ActivityLog ]
      resolve_filters
      # countish memoizes the COUNT in the page param, so it runs once per filter
      # change rather than once per page. Under the 30-day default that COUNT is a
      # range seek on index_activity_logs_on_created_at; on All-time it is a full
      # ordered walk of it, ~22 ms per million rows (#1130).
      @pagy, page = pagy(:countish, filtered_scope, limit: row_limit, max_limit: ALL_ROWS)
      @activities = page.for_feed
      # Page 1 only: "the first 500 of N" is true of the first page and false of
      # every one after it, which shows the ordinary Showing 501–1000 copy.
      @capped = @rows == "all" && @pagy.count > ALL_ROWS && @pagy.page == 1
      @top_actors = top_actors
    end

    private

    def resolve_filters
      @zone = Current.user.preferences&.time_zone || Time.zone
      @range = ActivityLog::Range.resolve(key: params[:range], from: params[:from], to: params[:to], zone: @zone)
      # `person` was the exact-email control this box replaces; it stays an
      # alias for one release so existing links and bookmarks keep filtering.
      @search = ActivityLog::Search.resolve(params[:q].presence || params[:person].presence,
                                            reach: operated_workspaces)
      # The NORMALIZED needle, so the box, the summary and every link the page
      # builds all say the one thing that was actually searched.
      @query = @search.query
      @workspace_param = params[:workspace].presence
      # include_discarded: a discarded workspace's rows are in this feed, so the
      # filter that isolates them has to be able to name it (#1170).
      @workspace = if @workspace_param && @workspace_param != "instance"
        operated_workspaces(include_discarded: true).find_by(slug: @workspace_param)
      end
      # A slug that resolves to nothing is a filter that MATCHED nothing, not an
      # absent filter. Dropping it here answered "any workspace" — the whole
      # ledger — to a question about one. The param is kept so the summary and
      # the empty state both say what was asked for.
      @workspace_unresolved = @workspace_param.present? &&
                              @workspace_param != "instance" && @workspace.nil?
      @kind = ActivityLog::KINDS.include?(params[:kind]) ? params[:kind] : nil
      @sort = SORTS.include?(params[:sort]) ? params[:sort] : DEFAULT_SORT
      @direction = params[:direction] == "asc" ? "asc" : "desc"
      @rows = ROWS.include?(params[:rows]) ? params[:rows] : DEFAULT_ROWS
      # The Workspace filter's options. Built here, not in the partial:
      # `operated_workspaces` is BaseController's private reach relation and
      # never a helper — a view has no door to it.
      resolve_workspace_picker
    end

    # Two shapes for one control. Under the limit it is the option list it has
    # always been; over it, a search — and crucially the list is never built, so
    # the payload stops scaling with the tenant count.
    def resolve_workspace_picker
      @workspace_picker_search = operated_workspaces.count > WORKSPACE_PICKER_LIMIT
      return resolve_workspace_query if @workspace_picker_search

      # The Workspace filter's options. Built here, not in the partial:
      # `operated_workspaces` is BaseController's private reach relation and
      # never a helper — a view has no door to it.
      @workspace_options = operated_workspaces.order(Arel.sql("LOWER(workspaces.name)"))
                             .map { |workspace| { value: workspace.slug, label: workspace.name } }
    end

    # A search names one workspace, several, or none — and only the first is a
    # filter. Guessing at "several" would apply a filter the operator did not
    # choose, so the page offers the choices instead.
    def resolve_workspace_query
      @workspace_query = params[:workspace_q].to_s.strip.presence
      # An explicit slug wins: it is what a shared link carries.
      return if @workspace_query.nil? || @workspace || @workspace_param == "instance"

      matches = ActivityLog::Search.workspaces_matching(@workspace_query, reach: operated_workspaces)
      @workspace_match_count = matches.count
      candidates = matches.order(Arel.sql("LOWER(workspaces.name)")).limit(WORKSPACE_CANDIDATE_LIMIT).to_a

      if @workspace_match_count == 1
        @workspace = candidates.first
        @workspace_param = @workspace.slug
      else
        @workspace_candidates = candidates
      end
    end

    def filtered_scope
      scope = ActivityLog.for_operations_feed.includes(:workspace)
      # A query that named nobody and nothing is a filter that matched, not an
      # absent filter — `none` is the honest answer, and it still responds to
      # `for_feed` (an empty Array) and to countish (count 0).
      if @query
        scope = @search.matched? ? scope.merge(search_scope) : scope.none
      end
      scope = scope.at_instance_level if @workspace_param == "instance"
      scope = scope.for_workspace(@workspace) if @workspace
      scope = scope.none if @workspace_unresolved
      scope = scope.of_kind(@kind) if @kind
      scope = scope.within(@range.from, @range.to) if @range.bounded?
      scope = scope.by_workspace_name(@direction) if @sort == "workspace"
      scope = scope.oldest_first if @sort == DEFAULT_SORT && @direction == "asc"
      scope
    end

    def search_scope
      ActivityLog.matching_any(users: @search.users, workspaces: @search.workspaces,
                               projects: @search.projects)
    end

    # The question an operator actually asks of a filtered window is "who has been
    # busiest here", and a Who sort answers it badly: it clusters names
    # alphabetically and then asks you to eyeball which block is tallest, across
    # pages. A count states it. (A Who sort is also impossible — actor names are
    # encrypted; see SORTS above.)
    #
    # A grouped count over the SAME filtered scope the table uses, on
    # `activity_logs.actor_id`, which is indexed. Two properties follow and both
    # matter: it counts every row that MATCHED rather than the rows that fitted on
    # this page, and only the handful of names actually shown are ever decrypted.
    def top_actors
      # `unscope(:includes)` — the workspace eager load exists to render rows, and
      # dragging it into a GROUP BY makes Rails build a query it cannot group.
      counts = filtered_scope.unscope(:includes)
                 .where.not(actor_id: nil)
                 .group(:actor_id)
                 # REORDER, not order: `for_operations_feed` already sorts by
                 # created_at DESC, and appending to that ranks by recency first
                 # and volume second — the most RECENT actor wins, not the
                 # busiest. actor_id breaks ties so the strip is stable.
                 .reorder(Arel.sql("COUNT(*) DESC, actor_id ASC"))
                 .limit(TOP_ACTORS)
                 .count
      return [] if counts.empty?

      actors = User.where(id: counts.keys).index_by(&:id)
      counts.filter_map { |id, count| actors[id] && [ actors[id], count ] }
    end

    def row_limit
      @rows == "all" ? ALL_ROWS : @rows.to_i
    end
  end
end
