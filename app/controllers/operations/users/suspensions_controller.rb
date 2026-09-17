module Operations
  module Users
    # The model verbs' guards make a repeat submit a no-op; the notice reports
    # the resulting state, which is true either way.
    class SuspensionsController < BaseController
      def create
        user = User.find(params[:user_id])
        authorize [ :operations, user ], :suspend?
        user.suspend!(by: Current.user)
        redirect_to operations_user_path(user), notice: t(".success")
      end

      def destroy
        user = User.find(params[:user_id])
        authorize [ :operations, user ], :unsuspend?
        user.unsuspend!(by: Current.user)
        redirect_to operations_user_path(user), notice: t(".success")
      end
    end
  end
end
