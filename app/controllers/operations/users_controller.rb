module Operations
  class UsersController < BaseController
    def index
      authorize [ :operations, User ]
      # Exact email only: email_address is deterministically encrypted (#902)
      # so equality search works; names aren't. Not the trust boundary —
      # `show` still resolves any id, and enumeration only matters once an
      # operator's reach is a real subset. See operations.md "What it
      # deliberately does not do" (scoped operators).
      @query = params[:q].to_s.strip
      @user = @query.present? ? User.find_by(email_address: @query) : nil
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
  end
end
