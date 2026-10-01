module Operations
  class UsersController < BaseController
    def index
      authorize [ :operations, User ]
      @query = params[:q].to_s.strip
      @search = User::Search.resolve(@query, scope: operated_users) if @query.present?
      @pagy, @users = pagy(:offset, listing.order(created_at: :desc))
    end

    def show
      @user = User.find(params[:id])
      authorize [ :operations, @user ]
      # SQLite's BINARY collation sorts uppercase before lowercase; LOWER()
      # gives a case-insensitive order (workspaces.name, unlike User's
      # encrypted names, can be sorted in SQL). `references(:workspace)` is
      # required too: without it `includes` preloads rather than joins, since
      # the raw LOWER(...) string doesn't match the plain `table.column`
      # shape Rails auto-detects a join from, and the ORDER BY hits an
      # unjoined table.
      @memberships = @user.memberships.kept.includes(:role, :workspace).references(:workspace)
        .order(Arel.sql("LOWER(workspaces.name)"))
    end

    private
      # Names resolve in Ruby; where(id:) keeps order and paging in SQL.
      def listing
        return operated_users unless @search

        operated_users.where(id: @search.ids)
      end
  end
end
