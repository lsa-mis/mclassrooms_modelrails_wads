module Operations
  class ActivityLogsController < BaseController
    ROWS         = %w[25 50 100 all].freeze
    # The two columns the ledger can order in SQL. Who is not among them: actor
    # names are encrypted (operations.md, "What it deliberately does not do").
    SORTS = %w[created_at workspace].freeze
    DEFAULT_SORT = "created_at"
    DEFAULT_ROWS = "50"
    # The cost of All is the page, not the decrypt: 500 rows of details is already a long
    # document, and an uncapped All on "All time" never finishes rendering.
    ALL_ROWS = 500
    # Past this many kept workspaces the filter becomes a search and the option list is not
    # built at all; a fork's instance crosses the line with nobody watching, so the page must.
    WORKSPACE_PICKER_LIMIT = 100
    # A search offers this many candidates and states the count it did not show.
    WORKSPACE_CANDIDATE_LIMIT = 20
    # Few enough to read at a glance: who has been busiest, not a breakdown.
    TOP_ACTORS = 5
    # Multiplies TOP_ACTORS so deleted actors cannot shorten the strip (#1250).
    TOP_ACTOR_OVERFETCH_FACTOR = 3

    def index
      authorize [ :operations, ActivityLog ]
      resolve_filters
      # countish memoizes the COUNT per filter change; ~22 ms per million rows (#1130).
      @pagy, page = pagy(:countish, filtered_scope, limit: row_limit, client_limit: ALL_ROWS)
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
      # `person` is the exact-email control this box replaced; kept so old links still filter.
      @search = ActivityLog::Search.resolve(params[:q].presence || params[:person].presence,
                                            reach: operated_workspaces)
      # The normalized needle, so the box, the summary and every link say the one thing searched.
      @query = @search.query
      @workspace_param = params[:workspace].presence
      # A discarded workspace's rows are in this feed, so the filter must name it (#1170).
      @workspace = if @workspace_param && @workspace_param != "instance"
        operated_workspaces(include_discarded: true).find_by(slug: @workspace_param)
      end
      # An unresolved slug matched nothing; dropping it would widen to the whole ledger.
      @workspace_unresolved = @workspace_param.present? &&
                              @workspace_param != "instance" && @workspace.nil?
      @kind = ActivityLog::KINDS.include?(params[:kind]) ? params[:kind] : nil
      @sort = SORTS.include?(params[:sort]) ? params[:sort] : DEFAULT_SORT
      @direction = params[:direction] == "asc" ? "asc" : "desc"
      @rows = ROWS.include?(params[:rows]) ? params[:rows] : DEFAULT_ROWS
      resolve_workspace_picker
    end

    # Under the limit, an option list; over it, a search, and the list is never built, so the
    # payload stops scaling with the tenant count.
    def resolve_workspace_picker
      @workspace_picker_search = operated_workspaces.count > WORKSPACE_PICKER_LIMIT
      return resolve_workspace_query if @workspace_picker_search

      # Built here, not in the partial: `operated_workspaces` is BaseController's private
      # reach relation, never a helper.
      @workspace_options = operated_workspaces.order(Arel.sql("LOWER(workspaces.name)"))
                             .map { |workspace| { value: workspace.slug, label: workspace.name } }
    end

    # A search names one workspace, several, or none, and only one is a filter; for several,
    # the page offers the choices rather than guessing.
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
      # The row's pivot reads the actor's live email; for_feed preloads only old rows.
      scope = ActivityLog.for_operations_feed.includes(:workspace, :actor)
      # A query that named nobody is a filter that matched nothing, not an absent filter;
      # `none` still answers for_feed (an empty Array) and countish (0).
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

    # A grouped count over the same filtered scope, on the indexed actor_id: every matched row
    # counts, and only the names shown are decrypted. A Who sort is impossible (SORTS above).
    def top_actors
      # The workspace eager load exists to render rows; dragged into a GROUP BY it makes a
      # query Rails cannot group.
      counts = filtered_scope.unscope(:includes)
                 .where.not(actor_id: nil)
                 .group(:actor_id)
                 # reorder, not order: the feed's created_at sort would rank by recency first;
                 # actor_id breaks ties so the strip is stable.
                 .reorder(Arel.sql("COUNT(*) DESC, actor_id ASC"))
                 # A deleted actor claims a slot here and drops out below (#1250).
                 .limit(TOP_ACTORS * TOP_ACTOR_OVERFETCH_FACTOR)
                 .count
      return [] if counts.empty?

      actors = User.where(id: counts.keys).index_by(&:id)
      counts.filter_map { |id, count| actors[id] && [ actors[id], count ] }
            .first(TOP_ACTORS)
    end

    def row_limit
      @rows == "all" ? ALL_ROWS : @rows.to_i
    end
  end
end
