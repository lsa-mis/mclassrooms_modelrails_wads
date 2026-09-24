module Operations
  module ActivityLedgerHelper
    # The only query params a ledger link may carry forward. An allow-list, not
    # a denylist: pagy reads `limit` straight off the query string, so passing
    # the whole of query_parameters through put a foreign `limit` on every Rows
    # link — where it wins over `rows` and makes the aria-current="true" a lie.
    FILTER_KEYS = %i[q workspace workspace_q kind range from to sort direction rows].freeze

    # How many matches of one kind the summary names before it counts the rest.
    SUMMARY_NAMES = 3

    # The applied state as one sentence: "128 events · Acme Robotics · members · 3–17 Sep 2026".
    # Rendered as the results <h2>, the page title, and the status announcement —
    # three calls per request, so memoized.
    def ledger_summary
      @ledger_summary ||= build_ledger_summary
    end

    def ledger_workspace_label
      return t("operations.activity_logs.index.instance") if @workspace_param == "instance"

      @workspace&.name || @workspace_param
    end

    def build_ledger_summary
      parts = [ t("operations.activity_logs.index.summary.events", count: @pagy.count) ]
      parts.concat(ledger_search_parts) if @query
      # @workspace can be nil while the param stands: a slug that resolves to
      # nothing is a filter that matched nothing, and the summary says which
      # slug was asked for rather than dropping the filter from the sentence
      # (#1170).
      parts << ledger_workspace_label if @workspace_param
      parts << t("activity.kinds.#{@kind}") if @kind
      parts << ledger_range_label
      parts.join(t("operations.activity_logs.index.summary.separator"))
    end

    # What the query resolved to, named: a search that matched can be read back
    # ("matching “priya”: Priya Nair, Priya Patel") and one that matched nothing
    # says so rather than looking like an empty instance.
    def ledger_search_parts
      parts = if @search.matched?
        [ t("operations.activity_logs.index.summary.matching", query: @query, names: ledger_search_names) ]
      else
        [ t("operations.activity_logs.index.summary.no_match", query: @query) ]
      end
      parts << t("operations.activity_logs.index.summary.names_skipped") if @search.names_skipped?
      parts
    end

    def ledger_search_names
      [ @search.users.map(&:full_name), @search.workspaces.map(&:name), @search.projects.map(&:name) ]
        .reject(&:empty?)
        .flat_map { |group| ledger_named_group(group) }
        .join(t("operations.activity_logs.index.summary.name_separator"))
    end

    def ledger_named_group(group)
      return group if group.size <= SUMMARY_NAMES

      group.first(SUMMARY_NAMES) +
        [ t("operations.activity_logs.index.summary.more", count: group.size - SUMMARY_NAMES) ]
    end

    def ledger_range_label
      return t("operations.activity_logs.index.ranges_long.all") if @range.all?
      return t("operations.activity_logs.index.ranges_long.#{@range.key}") unless @range.custom?

      t("operations.activity_logs.index.ranges.custom_trigger",
        from: l(@range.from_date, format: :ledger_short), to: l(@range.to_date, format: :ledger_day))
    end

    # The current filter params with overrides — every footer and pivot link
    # rebuilds the URL from this so no filter is lost, and nothing else rides
    # along (`page` and pagy's `limit` included).
    # `q` comes from the RESOLVED state, not the query string: a link arriving
    # on the `person` alias must carry its filter forward under the new name
    # rather than dropping it at the allow-list.
    def ledger_filter_params(**overrides)
      current = request.query_parameters.symbolize_keys.slice(*FILTER_KEYS)
      current[:q] = @query if @query
      current.merge(overrides).compact
    end

    def ledger_time(time)
      local = time.in_time_zone(@zone)
      tag.time(l(local, format: :ledger), datetime: time.iso8601, class: "tabular-nums whitespace-nowrap")
    end
  end
end
