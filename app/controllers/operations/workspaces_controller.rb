module Operations
  class WorkspacesController < BaseController
    # Operators honor deploy-time tenancy posture rather than bypassing it —
    # same as invite-only signup, which the operations area also doesn't skip.
    include RequiresWorkspaceCreationEnabled

    def index
      authorize [ :operations, Workspace ]
      # SQLite's default BINARY collation sorts uppercase before lowercase —
      # matches the sibling fix on Operations::UsersController#show.
      @pagy, @workspaces = pagy(:offset,
        operated_workspaces.includes(memberships: %i[role user]).order(Arel.sql("LOWER(workspaces.name)")))
    end

    def show
      @workspace = operated_workspaces.find_by!(slug: params[:slug])
      authorize [ :operations, @workspace ]
      # first_name/last_name are non-deterministically encrypted (user.rb's
      # `encrypts :pending_email, :first_name, :last_name` carries no
      # `deterministic: true`), so an SQL ORDER BY on either sorts
      # ciphertext, not names. Sort in Ruby on the decrypted values instead;
      # the eager loads below are unchanged, so this doesn't reintroduce a
      # query per row.
      @memberships = @workspace.memberships.kept.includes(:role, :user).to_a
        .sort_by { |m| [ m.user.last_name.to_s.downcase, m.user.first_name.to_s.downcase ] }
      @activities = @workspace.activity_logs.visible.recent.for_feed
    end

    def new
      authorize [ :operations, Workspace ]
      @workspace = Workspace.new
    end

    # What the verb does (existing user vs. unknown email, the transaction
    # boundary) lives on Workspace.create_for_owner_email; this action only
    # renders the outcome.
    def create
      authorize [ :operations, Workspace ]
      @workspace = Workspace.create_for_owner_email(create_params, operator: Current.user)

      if @workspace.persisted?
        redirect_to operations_workspace_path(@workspace), notice: t(".success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def create_params
      params.require(:workspace).permit(:name, :owner_email)
    end
  end
end
