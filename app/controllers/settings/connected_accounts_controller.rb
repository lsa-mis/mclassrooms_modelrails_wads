module Settings
  class ConnectedAccountsController < ApplicationController
    before_action :require_reauthentication!, only: :destroy
    layout "settings"

    def index
      @authentications = Current.user.authentications
    end

    def destroy
      destroyed_auth = nil

      destroyed = Authentication.transaction do
        # `.lock` issues SELECT FOR UPDATE on Postgres/MySQL. SQLite no-ops it,
        # but BEGIN IMMEDIATE (Rails default) gives database-wide write
        # serialization for the transaction's duration — same correctness.
        destroyed_auth = Current.user.authentications.lock.find(params[:id])

        if destroyed_auth.only_verified_remaining?
          false
        else
          destroyed_auth.destroy!
          true
        end
      end

      if destroyed
        redirect_to settings_connected_accounts_path,
          notice: t(".success", provider: destroyed_auth.display_provider)
      else
        redirect_to settings_connected_accounts_path,
          alert: t(".cannot_remove_last_verified")
      end
    end
  end
end
