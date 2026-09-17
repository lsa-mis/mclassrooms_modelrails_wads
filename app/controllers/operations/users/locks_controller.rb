module Operations
  module Users
    # User#unlock!'s guard makes a repeat submit a no-op; the notice reports
    # the resulting state, which is true either way.
    class LocksController < BaseController
      def destroy
        user = User.find(params[:user_id])
        authorize [ :operations, user ], :unlock?
        user.unlock!(by: Current.user)
        redirect_to operations_user_path(user), notice: t(".success")
      end
    end
  end
end
