module Account
  class ConnectedAccountsController < ApplicationController
    def index
      @authentications = Current.user.authentications
    end

    def destroy
      authentication = Current.user.authentications.find(params[:id])

      if Current.user.authentications.count <= 1
        redirect_to account_connected_accounts_path,
          alert: t(".last_method")
      else
        authentication.destroy!
        redirect_to account_connected_accounts_path,
          notice: t(".success", provider: authentication.provider.titleize)
      end
    end
  end
end
